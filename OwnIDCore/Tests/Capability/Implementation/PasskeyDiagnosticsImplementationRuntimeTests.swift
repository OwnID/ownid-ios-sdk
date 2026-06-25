import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

@Suite(.serialized)
struct PasskeyDiagnosticsImplementationRuntimeTests {

    @available(iOS 16.0, *)
    @Test func `Invalid RP ID reports validation failure and does not fetch diagnostics endpoints`() async throws {
        PasskeyDiagnosticsTestURLProtocol.reset()

        let sink = PasskeyDiagnosticsLogSink()
        let diagnostics = Self.makeDiagnostics(domain: "example.test", logger: sink)

        diagnostics.verify(rpId: "https://example.test")

        let report = try await Self.waitForReport(in: sink)
        #expect(report.message.contains("FAIL - Validate rpId - Contains scheme"))
        #expect(report.message.contains("SKIP - Fetch AASA - rpId validation failed"))
        #expect(report.message.contains("SKIP - Apple CDN - Missing rpId or application identifier"))
        #expect(PasskeyDiagnosticsTestURLProtocol.allRequests.isEmpty)
    }

    @available(iOS 16.0, *)
    @Test func `Valid entitlements AASA and CDN report pass and duplicate RP ID is skipped`() async throws {
        PasskeyDiagnosticsTestURLProtocol.reset()

        let domain = Self.uniqueDomain()
        Self.registerValidAASAAndCDN(for: domain)
        let sink = PasskeyDiagnosticsLogSink()
        let diagnostics = Self.makeDiagnostics(domain: domain, logger: sink)

        diagnostics.verify(rpId: domain.uppercased())
        diagnostics.verify(rpId: domain)

        let duplicate = try await sink.waitForEntry("duplicate RP ID log") {
            $0.message.contains("Skipping duplicate passkey diagnostics for rpId=\(domain)")
        }
        let report = try await Self.waitForReport(in: sink)

        #expect(duplicate.message.contains("Skipping duplicate passkey diagnostics"))
        #expect(report.message.contains("PasskeyDiagnostics: PASS"))
        #expect(report.message.contains("PASS - Validate rpId"))
        #expect(report.message.contains("PASS - Entitlements"))
        #expect(report.message.contains("PASS - Associated domains"))
        #expect(report.message.contains("PASS - Fetch AASA"))
        #expect(report.message.contains("PASS - Parse AASA"))
        #expect(report.message.contains("PASS - Consistency"))
        #expect(report.message.contains("PASS - Apple CDN"))
        #expect(PasskeyDiagnosticsTestURLProtocol.requests(to: Self.aasaURL(for: domain)).count == 1)
        #expect(PasskeyDiagnosticsTestURLProtocol.requests(to: Self.cdnURL(for: domain)).count == 1)
    }

    @available(iOS 16.0, *)
    @Test func `Missing application identifier reports entitlement failure and skips CDN`() async throws {
        PasskeyDiagnosticsTestURLProtocol.reset()

        let domain = Self.uniqueDomain()
        PasskeyDiagnosticsTestURLProtocol.register(
            .http(statusCode: 200, headers: Self.jsonHeaders, body: Self.validAASAData),
            for: Self.aasaURL(for: domain)
        )
        let sink = PasskeyDiagnosticsLogSink()
        let diagnostics = Self.makeDiagnostics(
            domain: domain,
            logger: sink,
            applicationIdentifier: nil,
            teamId: nil
        )

        diagnostics.verify(rpId: domain)

        let report = try await Self.waitForReport(in: sink)
        #expect(report.message.contains("FAIL - Entitlements - application-identifier missing"))
        #expect(report.message.contains("SKIP - Apple CDN - Missing rpId or application identifier"))
        #expect(PasskeyDiagnosticsTestURLProtocol.requests(to: Self.aasaURL(for: domain)).count == 1)
        #expect(PasskeyDiagnosticsTestURLProtocol.requests(to: Self.cdnURL(for: domain)).isEmpty)
    }

    @available(iOS 16.0, *)
    @Test(arguments: [
        AASAFailureCase(
            statusCode: 302,
            headers: ["Location": "https://redirected.example.test/aasa"],
            body: Data(),
            expectedReportFragment: "FAIL - Fetch AASA - Redirect not allowed"
        ),
        AASAFailureCase(
            statusCode: 200,
            headers: ["Content-Type": "text/plain"],
            body: Self.validAASAData,
            expectedReportFragment: "FAIL - Fetch AASA - Wrong Content-Type"
        ),
        AASAFailureCase(
            statusCode: 200,
            headers: Self.jsonHeaders,
            body: Data(repeating: UInt8(ascii: "a"), count: 131_073),
            expectedReportFragment: "FAIL - Fetch AASA - AASA exceeds 128 KB"
        ),
        AASAFailureCase(
            statusCode: 200,
            headers: Self.jsonHeaders,
            body: Data(#"{"webcredentials":{"apps":[]}}"#.utf8),
            expectedReportFragment: "FAIL - Parse AASA - webcredentials.apps missing"
        ),
    ])
    func `AASA fetch and parse failures are reported`(_ testCase: AASAFailureCase) async throws {
        PasskeyDiagnosticsTestURLProtocol.reset()

        let domain = Self.uniqueDomain()
        PasskeyDiagnosticsTestURLProtocol.register(
            .http(statusCode: testCase.statusCode, headers: testCase.headers, body: testCase.body),
            for: Self.aasaURL(for: domain)
        )
        PasskeyDiagnosticsTestURLProtocol.register(
            .http(statusCode: 200, headers: Self.jsonHeaders, body: Self.validCDNData),
            for: Self.cdnURL(for: domain)
        )
        let sink = PasskeyDiagnosticsLogSink()
        let diagnostics = Self.makeDiagnostics(domain: domain, logger: sink)

        diagnostics.verify(rpId: domain)

        let report = try await Self.waitForReport(in: sink)
        #expect(report.message.contains(testCase.expectedReportFragment))
        #expect(PasskeyDiagnosticsTestURLProtocol.requests(to: Self.aasaURL(for: domain)).count == 1)
    }

    @available(iOS 16.0, *)
    @Test func `CDN JSON parse failure is reported without live CDN access`() async throws {
        PasskeyDiagnosticsTestURLProtocol.reset()

        let domain = Self.uniqueDomain()
        PasskeyDiagnosticsTestURLProtocol.register(
            .http(statusCode: 200, headers: Self.jsonHeaders, body: Self.validAASAData),
            for: Self.aasaURL(for: domain)
        )
        PasskeyDiagnosticsTestURLProtocol.register(
            .http(statusCode: 200, headers: Self.jsonHeaders, body: Data("not-json".utf8)),
            for: Self.cdnURL(for: domain)
        )
        let sink = PasskeyDiagnosticsLogSink()
        let diagnostics = Self.makeDiagnostics(domain: domain, logger: sink)

        diagnostics.verify(rpId: domain)

        let report = try await Self.waitForReport(in: sink)
        #expect(report.message.contains("FAIL - Apple CDN - JSON parse error"))
        #expect(PasskeyDiagnosticsTestURLProtocol.requests(to: Self.cdnURL(for: domain)).count == 1)
    }

    private static let appIdentifier = "TEAMID.com.ownid.passkey.diagnostics.tests"
    private static let teamId = "TEAMID"
    private static let jsonHeaders = ["Content-Type": "application/json"]
    private static let validAASAData = Data(#"{"webcredentials":{"apps":["TEAMID.com.ownid.passkey.diagnostics.tests"]}}"#.utf8)
    private static let validCDNData = Data(#"{"domain":{"apps":["TEAMID.com.ownid.passkey.diagnostics.tests"]}}"#.utf8)

    @available(iOS 16.0, *)
    private static func makeDiagnostics(
        domain: String,
        logger: PasskeyDiagnosticsLogSink,
        applicationIdentifier: String? = appIdentifier,
        teamId: String? = teamId
    ) -> PasskeyDiagnosticsImpl {
        let router = OwnIDLogRouter(ownIDLoggerProvider: { logger }, serverLoggersProvider: { [] })
        return PasskeyDiagnosticsImpl(
            localInfo: PasskeyDiagnosticsLocalInfo(),
            logger: router,
            entitlementsOverride: (
                associatedDomains: ["webcredentials:\(domain)"],
                applicationIdentifier: applicationIdentifier,
                teamId: teamId
            ),
            sessionFactory: { configuration, delegate in
                configuration.protocolClasses = [PasskeyDiagnosticsTestURLProtocol.self]
                return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
            }
        )
    }

    private static func registerValidAASAAndCDN(for domain: String) {
        PasskeyDiagnosticsTestURLProtocol.register(
            .http(statusCode: 200, headers: jsonHeaders, body: validAASAData),
            for: aasaURL(for: domain)
        )
        PasskeyDiagnosticsTestURLProtocol.register(
            .http(statusCode: 200, headers: jsonHeaders, body: validCDNData),
            for: cdnURL(for: domain)
        )
    }

    private static func uniqueDomain() -> String {
        "passkey-\(UUID().uuidString.lowercased()).ownid.test"
    }

    private static func aasaURL(for domain: String) -> URL {
        URL(string: "https://\(domain)/.well-known/apple-app-site-association")!
    }

    private static func cdnURL(for domain: String) -> URL {
        URL(string: "https://app-site-association.cdn-apple.com/a/v1/\(domain)")!
    }

    private static func waitForReport(in sink: PasskeyDiagnosticsLogSink) async throws -> PasskeyDiagnosticsLogEntry {
        try await sink.waitForEntry("passkey diagnostics report") {
            $0.message.contains("PasskeyDiagnostics:")
        }
    }

}

struct AASAFailureCase: Sendable, CustomTestStringConvertible {
    let statusCode: Int
    let headers: [String: String]
    let body: Data
    let expectedReportFragment: String

    var testDescription: String { expectedReportFragment }
}

private struct PasskeyDiagnosticsLocalInfo: LocalInfo {
    let modules: [(name: String, version: String)] = [("OwnIDCore", "0.0.0")]
    let bundleID = "com.ownid.passkey.diagnostics.tests"
    let appVersion = "4.5.6"
    let userAgent = "OwnIDPasskeyDiagnosticsTests/4.5.6"
    let correlationId = "passkey-diagnostics-correlation-id"
    let isDebuggable = true
    let isSystemFidoCapable = true
    let isDeviceSecured = true
    let isFaceHardwarePresent = true
    let isFingerprintHardwarePresent = false
    let isStrongBiometricEnabled = true
}

private enum PasskeyDiagnosticsRoute: Sendable {
    case http(statusCode: Int, headers: [String: String], body: Data)
}

private final class PasskeyDiagnosticsURLProtocolRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var routes: [URL: PasskeyDiagnosticsRoute] = [:]
    private var recordedRequests: [URLRequest] = []

    func reset() {
        lock.withLock {
            routes.removeAll()
            recordedRequests.removeAll()
        }
    }

    func register(_ route: PasskeyDiagnosticsRoute, for url: URL) {
        lock.withLock {
            routes[url] = route
        }
    }

    func start(_ request: URLRequest) -> PasskeyDiagnosticsRoute? {
        lock.withLock {
            recordedRequests.append(request)
            guard let url = request.url else { return nil }
            return routes[url]
        }
    }

    func requests(to url: URL) -> [URLRequest] {
        lock.withLock {
            recordedRequests.filter { $0.url == url }
        }
    }

    var allRequests: [URLRequest] {
        lock.withLock { recordedRequests }
    }
}

private final class PasskeyDiagnosticsTestURLProtocol: URLProtocol {
    private static let registry = PasskeyDiagnosticsURLProtocolRegistry()

    static func reset() {
        registry.reset()
    }

    static func register(_ route: PasskeyDiagnosticsRoute, for url: URL) {
        registry.register(route, for: url)
    }

    static func requests(to url: URL) -> [URLRequest] {
        registry.requests(to: url)
    }

    static var allRequests: [URLRequest] {
        registry.allRequests
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url, let route = Self.registry.start(request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }

        switch route {
        case .http(let statusCode, let headers, let body):
            let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

private final class PasskeyDiagnosticsLogSink: OwnIDLogger, @unchecked Sendable {
    let level: LogLevel = .verbose
    let category = "OwnID-Passkey-Diagnostics-Test"

    private let recorder = AsyncSignalRecorder<PasskeyDiagnosticsLogEntry>()

    func log(level: LogLevel, className: String, message: String, cause: (any Error)?) {
        guard isEnabled(level) else { return }
        recorder.append(PasskeyDiagnosticsLogEntry(className: className, message: message))
    }

    func waitForEntry(
        _ timeoutDescription: String,
        seconds: UInt64 = 5,
        where predicate: @escaping @Sendable (PasskeyDiagnosticsLogEntry) -> Bool
    ) async throws -> PasskeyDiagnosticsLogEntry {
        try await recorder.waitForFirst(timeoutDescription, seconds: seconds, where: predicate)
    }
}

private struct PasskeyDiagnosticsLogEntry: Sendable {
    let className: String
    let message: String
}
