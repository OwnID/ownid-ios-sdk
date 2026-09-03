import Compression
import Foundation

/// Best-effort runtime diagnostics for iOS passkey relying-party configuration.
///
/// Verification runs at most once per normalized RP ID. It reports origin and Apple CDN AASA observations through
/// the SDK logger only; diagnostics do not gate or authorize passkey operations.
@available(iOS 16.0, *)
internal final class PasskeyDiagnosticsImpl: PasskeyDiagnostics {
    private enum Status: String {
        case pass = "PASS"
        case warn = "WARN"
        case fail = "FAIL"
        case skip = "SKIP"
    }

    private struct Step {
        let name: String
        let status: Status
        let reason: String?
        let details: [String: String]

        init(_ name: String, status: Status, reason: String? = nil, details: [String: String] = [:]) {
            self.name = name
            self.status = status
            self.reason = reason
            self.details = details
        }

        static func pass(_ name: String, details: [String: String] = [:]) -> Step {
            Step(name, status: .pass, details: details)
        }

        static func warn(_ name: String, reason: String, details: [String: String] = [:]) -> Step {
            Step(name, status: .warn, reason: reason, details: details)
        }

        static func fail(_ name: String, reason: String, details: [String: String] = [:]) -> Step {
            Step(name, status: .fail, reason: reason, details: details)
        }

        static func skip(_ name: String, reason: String, details: [String: String] = [:]) -> Step {
            Step(name, status: .skip, reason: reason, details: details)
        }
    }

    private struct AASAInfo {
        let apps: [String]
    }

    private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }

    private final class VerifiedRpIds: @unchecked Sendable {
        private let lock = NSLock()
        private var values = Set<String>()

        func insert(_ value: String) -> Bool {
            lock.withLock { values.insert(value).inserted }
        }
    }

    private let localInfo: any LocalInfo
    private let logger: OwnIDLogRouter?
    private let sessionFactory: @Sendable (URLSessionConfiguration, (any URLSessionTaskDelegate)?) -> URLSession
    private let verifiedRpIds = VerifiedRpIds()

    init(
        localInfo: any LocalInfo,
        logger: OwnIDLogRouter?,
        sessionFactory: @escaping @Sendable (URLSessionConfiguration, (any URLSessionTaskDelegate)?) -> URLSession = {
            URLSession(configuration: $0, delegate: $1, delegateQueue: nil)
        }
    ) {
        self.localInfo = localInfo
        self.logger = logger
        self.sessionFactory = sessionFactory
    }

    func verify(rpId: String) {
        let key = rpId.lowercased()
        guard verifiedRpIds.insert(key) else {
            logger?.logV(source: Self.self, prefix: "verify", message: "Skipping duplicate passkey diagnostics for rpId=\(key)")
            return
        }

        _ = Task.detached(priority: .utility) { [self, rpId] in
            await runDiagnostics(rpId: rpId)
        }
    }

    private func runDiagnostics(rpId: String) async {
        let bundleId = localInfo.bundleID
        var steps: [Step] = []
        var cdnApps: [String] = []

        let rpResult = validateRpId(rpId)
        steps.append(rpResult.step)
        let normalizedRpId = rpResult.normalizedRpId

        var aasaPayload: (data: Data, response: HTTPURLResponse)?
        if let domain = normalizedRpId {
            let fetch = await fetchAASA(for: domain)
            steps.append(fetch.step)
            aasaPayload = fetch.payload
        } else {
            steps.append(.skip("Fetch AASA", reason: "rpId validation failed"))
        }

        var aasaInfo: AASAInfo?
        if let payload = aasaPayload {
            let parse = parseAASA(payload: payload)
            steps.append(parse.step)
            aasaInfo = parse.info
        } else {
            steps.append(.skip("Parse AASA", reason: "AASA not fetched"))
        }

        if let info = aasaInfo {
            steps.append(checkBundleIdentifierMembership(name: "Origin AASA", apps: info.apps, bundleId: bundleId))
        } else {
            steps.append(.skip("Origin AASA", reason: "AASA data unavailable"))
        }

        if let domain = normalizedRpId {
            let cdn = await fetchCDN(domain: domain, bundleId: bundleId)
            steps.append(cdn.step)
            cdnApps = cdn.apps
        } else {
            steps.append(.skip("Apple CDN", reason: "rpId validation failed"))
        }

        let report = buildReport(
            steps: steps,
            bundleId: bundleId,
            aasaApps: aasaInfo?.apps ?? [],
            cdnApps: cdnApps
        )
        await MainActor.run {
            logger?.logW(source: Self.self, prefix: "verify", message: report)
        }
    }

    private func buildReport(steps: [Step], bundleId: String, aasaApps: [String], cdnApps: [String]) -> String {
        let summary: Status
        if steps.contains(where: { $0.status == .fail }) {
            summary = .fail
        } else if steps.contains(where: { $0.status == .warn }) {
            summary = .warn
        } else if steps.contains(where: { $0.status == .pass }) {
            summary = .pass
        } else {
            summary = .skip
        }

        var builder = "\nPasskeyDiagnostics: \(summary.rawValue)\n"
        builder += "Env: Application bundleId=\(bundleId), version=\(localInfo.appVersion), debuggable=\(localInfo.isDebuggable)\n"
        builder += "Env: correlationId=\(localInfo.correlationId)\n"
        builder +=
            "Env: isSystemFidoCapable=\(localInfo.isSystemFidoCapable), isDeviceSecured=\(localInfo.isDeviceSecured), isStrongBiometricEnabled=\(localInfo.isStrongBiometricEnabled)\n"
        if !aasaApps.isEmpty || !cdnApps.isEmpty {
            func formatList(_ items: [String]) -> String {
                items.isEmpty ? "-" : items.joined(separator: ", ")
            }
            builder += "Env: AASA.apps=\(formatList(aasaApps)), CDN.apps=\(formatList(cdnApps))\n"
        }
        for step in steps {
            builder += "\n\(step.status.rawValue) - \(step.name)"
            if let reason = step.reason { builder += " - \(reason)" }
            if !step.details.isEmpty {
                let kv = step.details.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
                builder += " [\(kv)]"
            }
        }
        return builder
    }

    private func validateRpId(_ input: String) -> (step: Step, normalizedRpId: String?) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (.fail("Validate rpId", reason: "Empty rpId"), nil) }
        guard trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            return (.fail("Validate rpId", reason: "Contains whitespace"), nil)
        }
        if trimmed.contains("://") { return (.fail("Validate rpId", reason: "Contains scheme"), nil) }
        if trimmed.contains("@") { return (.fail("Validate rpId", reason: "Contains user info"), nil) }
        if trimmed.contains("/") { return (.fail("Validate rpId", reason: "Contains path"), nil) }
        if trimmed.hasSuffix(":") || trimmed.contains(":") {
            return (.fail("Validate rpId", reason: "Contains port or IPv6 literal"), nil)
        }

        guard let components = URLComponents(string: "https://\(trimmed)"),
            let host = components.host, !host.isEmpty
        else {
            return (.fail("Validate rpId", reason: "Malformed host"), nil)
        }
        if host.count > 253 { return (.fail("Validate rpId", reason: "Host too long"), nil) }
        if isIPv4(host) { return (.fail("Validate rpId", reason: "Host is IPv4 address"), nil) }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let alphanumerics = CharacterSet.alphanumerics
        for label in host.split(separator: ".") {
            guard !label.isEmpty else { return (.fail("Validate rpId", reason: "Empty label"), nil) }
            guard label.count <= 63 else {
                return (.fail("Validate rpId", reason: "Label too long", details: ["label": String(label)]), nil)
            }
            guard let first = label.first, let last = label.last,
                first.unicodeScalars.allSatisfy({ alphanumerics.contains($0) }),
                last.unicodeScalars.allSatisfy({ alphanumerics.contains($0) })
            else {
                return (.fail("Validate rpId", reason: "Label edge must be alphanumeric", details: ["label": String(label)]), nil)
            }
            if label.unicodeScalars.contains(where: { !allowed.contains($0) }) {
                return (.fail("Validate rpId", reason: "Invalid label characters", details: ["label": String(label)]), nil)
            }
        }

        let normalized = host.lowercased()
        return (.pass("Validate rpId", details: ["rpId": normalized]), normalized)
    }

    private func fetchAASA(for domain: String) async -> (step: Step, payload: (data: Data, response: HTTPURLResponse)?) {
        guard let url = URL(string: "https://\(domain)/.well-known/apple-app-site-association") else {
            return (.fail("Fetch AASA", reason: "Invalid URL", details: ["domain": domain]), nil)
        }
        return await fetch(url: url, name: "Fetch AASA", enforceJSON: true, checkSize: true)
    }

    private func fetchCDN(domain: String, bundleId: String) async -> (step: Step, apps: [String]) {
        guard let url = URL(string: "https://app-site-association.cdn-apple.com/a/v1/\(domain)") else {
            return (.fail("Apple CDN", reason: "Invalid CDN URL", details: ["domain": domain]), [])
        }
        let fetch = await fetch(
            url: url,
            name: "Apple CDN",
            enforceJSON: false,
            checkSize: false,
            failureHeaders: ["Apple-Failure-Reason", "Apple-Failure-Details", "Apple-From"]
        )
        guard let payload = fetch.payload else { return (fetch.step, []) }
        do {
            let json = try JSONSerialization.jsonObject(with: payload.data, options: [])
            guard let apps = extractApps(from: json), !apps.isEmpty else {
                return (.fail("Apple CDN", reason: "webcredentials.apps missing"), [])
            }
            let membership = checkBundleIdentifierMembership(name: "Apple CDN", apps: apps, bundleId: bundleId)
            return (membership, apps)
        } catch {
            return (.fail("Apple CDN", reason: "JSON parse error", details: ["error": error.localizedDescription]), [])
        }
    }

    private func fetch(url: URL, name: String, enforceJSON: Bool, checkSize: Bool, failureHeaders: [String] = []) async -> (
        step: Step, payload: (data: Data, response: HTTPURLResponse)?
    ) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(localInfo.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("en", forHTTPHeaderField: "Accept-Language")

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        let delegate = NoRedirectDelegate()
        let session = sessionFactory(config, delegate)
        defer { session.invalidateAndCancel() }

        do {
            let (data, response) = try await session.dataCompat(for: request, delegate: nil)
            guard let http = response as? HTTPURLResponse else { return (.fail(name, reason: "Non-HTTP response"), nil) }
            if (300..<400).contains(http.statusCode) {
                var details: [String: String] = ["code": "\(http.statusCode)", "url": url.absoluteString]
                for header in failureHeaders {
                    if let value = http.value(forHTTPHeaderField: header) {
                        details[header] = value
                    }
                }
                return (.fail(name, reason: "Redirect not allowed", details: details), nil)
            }
            guard http.statusCode == 200 else {
                var details: [String: String] = ["code": "\(http.statusCode)", "url": url.absoluteString]
                for header in failureHeaders {
                    if let value = http.value(forHTTPHeaderField: header) {
                        details[header] = value
                    }
                }
                return (.fail(name, reason: "HTTP \(http.statusCode)", details: details), nil)
            }
            if enforceJSON {
                let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
                if !contentType.starts(with: "application/json") {
                    return (.fail(name, reason: "Wrong Content-Type", details: ["contentType": contentType]), nil)
                }
            }
            var finalData = data
            let encodingHeader = http.value(forHTTPHeaderField: "Content-Encoding") ?? ""
            let normalizedEncoding = encodingHeader.lowercased()
            if checkSize {
                if !normalizedEncoding.isEmpty && normalizedEncoding != "identity" {
                    guard let decompressed = decompressBody(data, encoding: normalizedEncoding) else {
                        return (
                            .fail(name, reason: "Failed to decompress AASA", details: ["encoding": normalizedEncoding]),
                            nil
                        )
                    }
                    finalData = decompressed
                }
                if finalData.count > 131_072 {
                    return (.fail(name, reason: "AASA exceeds 128 KB", details: ["size": "\(finalData.count)"]), nil)
                }
            }
            var details: [String: String] = ["code": "\(http.statusCode)", "size": "\(finalData.count)"]
            if let contentType = http.value(forHTTPHeaderField: "Content-Type") { details["contentType"] = contentType }
            if !encodingHeader.isEmpty { details["contentEncoding"] = encodingHeader }
            return (.pass(name, details: details), (finalData, http))
        } catch {
            if let urlError = error as? URLError {
                let details = ["code": "\(urlError.code.rawValue)", "url": url.absoluteString]
                switch urlError.code {
                case .timedOut, .networkConnectionLost, .notConnectedToInternet:
                    return (.warn(name, reason: "Network unavailable", details: details), nil)
                default:
                    return (.fail(name, reason: "Network error", details: details), nil)
                }
            }
            return (.fail(name, reason: "Error", details: ["error": error.localizedDescription]), nil)
        }
    }

    private func decompressBody(_ data: Data, encoding: String) -> Data? {
        let primary = encoding.split(separator: ",").first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""

        switch primary {
        case "", "identity":
            return data
        case "gzip", "x-gzip":
            if let inflated = try? (data as NSData).decompressed(using: .zlib) as Data {
                return inflated
            }
            guard data.count > 18 else { return nil }
            let start: Data.Index = 10
            let end: Data.Index = data.count - 8
            guard end > start else { return nil }
            let range: Range<Data.Index> = start..<end
            let trimmedData = data.subdata(in: range)
            return try? (trimmedData as NSData).decompressed(using: .zlib) as Data
        case "deflate", "compress", "zlib":
            return try? (data as NSData).decompressed(using: .zlib) as Data
        default:
            return nil
        }
    }

    private func isIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { segment in
            guard !segment.isEmpty,
                segment.allSatisfy(\.isNumber),
                let value = Int(segment),
                (0...255).contains(value)
            else {
                return false
            }
            return true
        }
    }

    private func parseAASA(payload: (data: Data, response: HTTPURLResponse)) -> (step: Step, info: AASAInfo?) {
        do {
            let json = try JSONSerialization.jsonObject(with: payload.data, options: [])
            guard let apps = extractApps(from: json), !apps.isEmpty else {
                return (.fail("Parse AASA", reason: "webcredentials.apps missing"), nil)
            }
            return (
                .pass("Parse AASA", details: ["apps": apps.joined(separator: ";")]),
                AASAInfo(apps: apps)
            )
        } catch {
            return (.fail("Parse AASA", reason: "JSON parse error", details: ["error": error.localizedDescription]), nil)
        }
    }

    private func extractApps(from json: Any) -> [String]? {
        guard let dict = json as? [String: Any],
            let webcredentials = dict["webcredentials"] as? [String: Any],
            let apps = webcredentials["apps"] as? [String]
        else {
            return nil
        }
        return apps
    }

    private func checkBundleIdentifierMembership(name: String, apps: [String], bundleId: String) -> Step {
        if let match = apps.first(where: { appEntryMatchesBundleIdentifier($0, bundleId: bundleId) }) {
            return .pass(name, details: ["bundleId": bundleId, "matchedAppEntry": match])
        }
        return .fail(
            name,
            reason: "No webcredentials.apps entry matches the application Bundle ID",
            details: ["bundleId": bundleId, "apps": apps.joined(separator: ";")]
        )
    }

    private func appEntryMatchesBundleIdentifier(_ appEntry: String, bundleId: String) -> Bool {
        guard let separator = appEntry.firstIndex(of: "."), separator != appEntry.startIndex else { return false }
        let candidateStart = appEntry.index(after: separator)
        let candidate = appEntry[candidateStart...]
        guard !candidate.isEmpty, candidate.utf8.count == bundleId.utf8.count else { return false }

        return zip(candidate.utf8, bundleId.utf8).allSatisfy { lhs, rhs in
            guard lhs < 128, rhs < 128 else { return false }
            return asciiLowercased(lhs) == asciiLowercased(rhs)
        }
    }

    private func asciiLowercased(_ byte: UInt8) -> UInt8 {
        (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte) ? byte + 32 : byte
    }
}
