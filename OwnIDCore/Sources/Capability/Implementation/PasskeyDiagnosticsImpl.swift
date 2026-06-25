import Compression
import Foundation
import Security

private typealias SecTaskRef = CFTypeRef

@_silgen_name("SecTaskCreateFromSelf")
private func SecTaskCreateFromSelf(_ allocator: CFAllocator?) -> SecTaskRef?

@_silgen_name("SecTaskCopyValueForEntitlement")
private func SecTaskCopyValueForEntitlement(
    _ task: SecTaskRef,
    _ entitlement: CFString,
    _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?
) -> CFTypeRef?

/// Best-effort runtime diagnostics for iOS passkey relying-party configuration.
///
/// Verification runs at most once per normalized RP ID. It reports entitlement, AASA, robots.txt, and app-site
/// association findings through the SDK logger only; diagnostics do not gate or authorize passkey operations.
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

    private struct EntitlementsInfo {
        let associatedDomains: [String]
        let applicationIdentifier: String?
        let teamId: String?
    }

    private struct AASAInfo {
        let apps: [String]
        let rawJSONSize: Int
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
    private let entitlementsInfo: EntitlementsInfo
    private let sessionFactory: @Sendable (URLSessionConfiguration, (any URLSessionTaskDelegate)?) -> URLSession
    private let verifiedRpIds = VerifiedRpIds()

    init(
        localInfo: any LocalInfo,
        logger: OwnIDLogRouter?,
        entitlementsOverride: (associatedDomains: [String], applicationIdentifier: String?, teamId: String?)? = nil,
        sessionFactory: @escaping @Sendable (URLSessionConfiguration, (any URLSessionTaskDelegate)?) -> URLSession = {
            URLSession(configuration: $0, delegate: $1, delegateQueue: nil)
        }
    ) {
        self.localInfo = localInfo
        self.logger = logger
        self.sessionFactory = sessionFactory
        if let override = entitlementsOverride {
            self.entitlementsInfo = EntitlementsInfo(
                associatedDomains: override.associatedDomains,
                applicationIdentifier: override.applicationIdentifier,
                teamId: override.teamId
            )
        } else {
            self.entitlementsInfo = Self.loadEntitlements()
        }
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

    private static func loadEntitlements() -> EntitlementsInfo {
        guard let task = SecTaskCreateFromSelf(nil) else {
            return EntitlementsInfo(associatedDomains: [], applicationIdentifier: nil, teamId: nil)
        }

        let appId = SecTaskCopyValueForEntitlement(task, "application-identifier" as CFString, nil) as? String

        var associatedDomains: [String] = []
        if let raw = SecTaskCopyValueForEntitlement(task, "com.apple.developer.associated-domains" as CFString, nil) {
            if let list = raw as? [String] {
                associatedDomains = list
            } else if let anyList = raw as? [Any] {
                associatedDomains = anyList.compactMap { $0 as? String }
            }
        }

        let teamId = appId?.split(separator: ".").first.map(String.init)
        return EntitlementsInfo(associatedDomains: associatedDomains, applicationIdentifier: appId, teamId: teamId)
    }

    private func runDiagnostics(rpId: String) async {
        let bundleId = localInfo.bundleID
        var steps: [Step] = []
        var cdnApps: [String] = []

        let rpResult = validateRpId(rpId)
        steps.append(rpResult.step)
        let normalizedRpId = rpResult.normalizedRpId

        steps.append(buildEntitlementsStep(info: entitlementsInfo))
        let expectedAppId = entitlementsInfo.teamId.map { "\($0).\(bundleId)" }

        if let domain = normalizedRpId, !entitlementsInfo.associatedDomains.isEmpty {
            steps.append(checkAssociatedDomains(domain: domain, entries: entitlementsInfo.associatedDomains))
        } else {
            let reason = normalizedRpId == nil ? "rpId validation failed" : "Associated domains missing"
            steps.append(.skip("Associated domains", reason: reason))
        }

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

        if let info = aasaInfo, let appId = entitlementsInfo.applicationIdentifier, let expected = expectedAppId {
            steps.append(checkConsistency(expected: expected, appId: appId, apps: info.apps))
        } else {
            steps.append(.skip("Consistency", reason: "Missing entitlement or AASA data"))
        }

        if let domain = normalizedRpId, let expected = entitlementsInfo.applicationIdentifier ?? expectedAppId {
            let cdn = await fetchCDN(domain: domain, expectedAppId: expected)
            steps.append(cdn.step)
            cdnApps = cdn.apps
        } else {
            steps.append(.skip("Apple CDN", reason: "Missing rpId or application identifier"))
        }

        let report = buildReport(
            steps: steps,
            bundleId: bundleId,
            entitlements: entitlementsInfo,
            aasaApps: aasaInfo?.apps ?? [],
            cdnApps: cdnApps
        )
        await MainActor.run {
            logger?.logW(source: Self.self, prefix: "verify", message: report)
        }
    }

    private func buildReport(steps: [Step], bundleId: String, entitlements: EntitlementsInfo, aasaApps: [String], cdnApps: [String])
        -> String
    {
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
        builder +=
            "Env: AppID=\(entitlements.applicationIdentifier ?? "n/a"), teamId=\(entitlements.teamId ?? "n/a"), correlationId=\(localInfo.correlationId)\n"
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

    private func buildEntitlementsStep(info: EntitlementsInfo) -> Step {
        var details: [String: String] = [:]
        details["associatedDomains"] = info.associatedDomains.joined(separator: ";")
        if let appId = info.applicationIdentifier { details["appId"] = appId }
        if let teamId = info.teamId { details["teamId"] = teamId }

        if info.applicationIdentifier == nil {
            return .fail("Entitlements", reason: "application-identifier missing", details: details)
        }
        if info.associatedDomains.isEmpty {
            return .fail("Entitlements", reason: "No associated domains", details: details)
        }
        if let appId = info.applicationIdentifier, !appId.hasSuffix(".\(localInfo.bundleID)") {
            details["bundleId"] = localInfo.bundleID
            return .fail("Entitlements", reason: "AppID does not match bundle", details: details)
        }
        return .pass("Entitlements", details: details)
    }

    private func checkAssociatedDomains(domain: String, entries: [String]) -> Step {
        let match = entries.first(where: { matches(domain: domain, entry: $0) })
        if let matched = match {
            return .pass("Associated domains", details: ["match": matched])
        }
        return .fail("Associated domains", reason: "webcredentials entry missing", details: ["domain": domain])
    }

    private func matches(domain: String, entry: String) -> Bool {
        let prefix = "webcredentials:"
        guard entry.hasPrefix(prefix) else { return false }
        let value = entry.dropFirst(prefix.count)
        if value.hasPrefix("*.") {
            let base = value.dropFirst(2)
            guard !base.isEmpty else { return false }
            let suffix = "." + base
            return domain.count > suffix.count && domain.hasSuffix(suffix)
        } else {
            return domain == value
        }
    }

    private func fetchAASA(for domain: String) async -> (step: Step, payload: (data: Data, response: HTTPURLResponse)?) {
        guard let url = URL(string: "https://\(domain)/.well-known/apple-app-site-association") else {
            return (.fail("Fetch AASA", reason: "Invalid URL", details: ["domain": domain]), nil)
        }
        return await fetch(url: url, name: "Fetch AASA", enforceJSON: true, checkSize: true)
    }

    private func fetchCDN(domain: String, expectedAppId: String) async -> (step: Step, apps: [String]) {
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
            let apps = extractApps(from: json)
            if apps.contains(expectedAppId) {
                return (.pass("Apple CDN", details: ["code": "\(payload.response.statusCode)"]), apps)
            } else {
                return (
                    .fail(
                        "Apple CDN",
                        reason: "AppID missing in CDN view",
                        details: ["code": "\(payload.response.statusCode)", "apps": apps.joined(separator: ";")]
                    ), apps
                )
            }
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
                return (
                    .fail(name, reason: "Network error", details: ["code": "\(urlError.code.rawValue)", "url": url.absoluteString]), nil
                )
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
            let apps = extractApps(from: json)
            if apps.isEmpty {
                return (.fail("Parse AASA", reason: "webcredentials.apps missing"), nil)
            }
            return (
                .pass("Parse AASA", details: ["apps": apps.joined(separator: ";")]),
                AASAInfo(apps: apps, rawJSONSize: payload.data.count)
            )
        } catch {
            return (.fail("Parse AASA", reason: "JSON parse error", details: ["error": error.localizedDescription]), nil)
        }
    }

    private func extractApps(from json: Any) -> [String] {
        guard let dict = json as? [String: Any] else { return [] }
        if let webcredentials = dict["webcredentials"] as? [String: Any], let apps = webcredentials["apps"] as? [Any] {
            return apps.compactMap { $0 as? String }
        }
        // Some CDN responses wrap domains
        for value in dict.values {
            if let nested = value as? [String: Any], let apps = nested["apps"] as? [String] {
                return apps
            }
            if let array = value as? [Any] {
                for element in array {
                    let apps = extractApps(from: element)
                    if !apps.isEmpty { return apps }
                }
            }
        }
        return []
    }

    private func checkConsistency(expected: String, appId: String, apps: [String]) -> Step {
        if appId != expected {
            return .fail("Consistency", reason: "application-identifier mismatch", details: ["appId": appId, "expected": expected])
        }
        if apps.contains(expected) {
            return .pass("Consistency", details: ["appId": expected])
        }
        return .fail("Consistency", reason: "AppID missing in AASA", details: ["expected": expected, "apps": apps.joined(separator: ";")])
    }
}
