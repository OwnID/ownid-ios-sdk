import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

// Covers: DIAG-RUNTIME-040
@Suite(.serialized)
struct PasskeyDiagnosticsImplementationRuntimeTests {

    @available(iOS 16.0, *)
    @Test func `Invalid RP ID reports validation failure and does not fetch diagnostics endpoints`() async throws {
        PasskeyDiagnosticsTestURLProtocol.reset()

        let sink = PasskeyDiagnosticsLogSink()
        let diagnostics = Self.makeDiagnostics(logger: sink)

        diagnostics.verify(rpId: "https://example.test")

        let report = try await Self.waitForReport(in: sink)
        #expect(report.message.contains("FAIL - Validate rpId - Contains scheme"))
        #expect(report.message.contains("SKIP - Fetch AASA - rpId validation failed"))
        #expect(report.message.contains("SKIP - Apple CDN - rpId validation failed"))
        #expect(PasskeyDiagnosticsTestURLProtocol.allRequests.isEmpty)
    }

    @available(iOS 16.0, *)
    @Test func `Origin and CDN accept arbitrary App ID prefixes and duplicate normalized RP ID is skipped`() async throws {
        PasskeyDiagnosticsTestURLProtocol.reset()

        let domain = Self.uniqueDomain()
        let originEntry = "ORIGINPREFIX.\(Self.bundleID)"
        let cdnEntry = "DIFFERENTPREFIX.\(Self.bundleID)"
        Self.registerAASAAndCDN(for: domain, originApps: [originEntry], cdnApps: [cdnEntry])
        let sink = PasskeyDiagnosticsLogSink()
        let diagnostics = Self.makeDiagnostics(logger: sink)

        diagnostics.verify(rpId: domain.uppercased())
        diagnostics.verify(rpId: domain)

        let duplicate = try await sink.waitForEntry("duplicate RP ID log") {
            $0.message.contains("Skipping duplicate passkey diagnostics for rpId=\(domain)")
        }
        let report = try await Self.waitForReport(in: sink)

        #expect(duplicate.message.contains("Skipping duplicate passkey diagnostics"))
        #expect(report.message.contains("PasskeyDiagnostics: PASS"))
        #expect(report.message.contains("PASS - Validate rpId"))
        #expect(report.message.contains("PASS - Fetch AASA"))
        #expect(report.message.contains("PASS - Parse AASA"))
        #expect(report.message.contains("PASS - Origin AASA"))
        #expect(report.message.contains("PASS - Apple CDN"))
        #expect(report.message.contains("AASA.apps=\(originEntry)"))
        #expect(report.message.contains("CDN.apps=\(cdnEntry)"))
        #expect(PasskeyDiagnosticsTestURLProtocol.requests(to: Self.aasaURL(for: domain)).count == 1)
        #expect(PasskeyDiagnosticsTestURLProtocol.requests(to: Self.cdnURL(for: domain)).count == 1)
    }

    @available(iOS 16.0, *)
    @Test func `Origin and CDN Bundle ID candidate matching is ASCII case insensitive`() async throws {
        PasskeyDiagnosticsTestURLProtocol.reset()

        let domain = Self.uniqueDomain()
        let caseVariedBundleID = Self.bundleID.uppercased()
        Self.registerAASAAndCDN(
            for: domain,
            originApps: ["PREFIX.\(caseVariedBundleID)"],
            cdnApps: ["OTHER.\(caseVariedBundleID)"]
        )
        let sink = PasskeyDiagnosticsLogSink()
        let diagnostics = Self.makeDiagnostics(logger: sink)

        diagnostics.verify(rpId: domain)

        let report = try await Self.waitForReport(in: sink)
        #expect(report.message.contains("PASS - Origin AASA"))
        #expect(report.message.contains("PASS - Apple CDN"))
    }

    @available(iOS 16.0, *)
    @Test(arguments: [
        BundleCandidateFailureCase(appEntry: "PREFIX.com.example.other", description: "different Bundle ID"),
        BundleCandidateFailureCase(
            appEntry: "PREFIX.\(PasskeyDiagnosticsLocalInfo.bundleIdentifier).deceptive",
            description: "deceptive longer Bundle ID"
        ),
    ])
    func `Origin and CDN reject nonmatching Bundle ID candidates`(_ testCase: BundleCandidateFailureCase) async throws {
        PasskeyDiagnosticsTestURLProtocol.reset()

        let domain = Self.uniqueDomain()
        Self.registerAASAAndCDN(for: domain, originApps: [testCase.appEntry], cdnApps: [testCase.appEntry])
        let sink = PasskeyDiagnosticsLogSink()
        let diagnostics = Self.makeDiagnostics(logger: sink)

        diagnostics.verify(rpId: domain)

        let report = try await Self.waitForReport(in: sink)
        #expect(report.message.contains("FAIL - Origin AASA - No webcredentials.apps entry matches the application Bundle ID"))
        #expect(report.message.contains("FAIL - Apple CDN - No webcredentials.apps entry matches the application Bundle ID"))
        #expect(report.message.contains(testCase.appEntry))
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
            statusCode: 503,
            headers: Self.jsonHeaders,
            body: Data(),
            expectedReportFragment: "FAIL - Fetch AASA - HTTP 503"
        ),
        AASAFailureCase(
            statusCode: 200,
            headers: ["Content-Type": "text/plain"],
            body: Self.aasaData(apps: [Self.validAppEntry]),
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
            body: Data("not-json".utf8),
            expectedReportFragment: "FAIL - Parse AASA - JSON parse error"
        ),
        AASAFailureCase(
            statusCode: 200,
            headers: Self.jsonHeaders,
            body: Data(#"{"webcredentials":{"apps":[]}}"#.utf8),
            expectedReportFragment: "FAIL - Parse AASA - webcredentials.apps missing"
        ),
        AASAFailureCase(
            statusCode: 200,
            headers: Self.jsonHeaders,
            body: Data(#"{"webcredentials":{"apps":"PREFIX.com.ownid.passkey.diagnostics.tests"}}"#.utf8),
            expectedReportFragment: "FAIL - Parse AASA - webcredentials.apps missing"
        ),
        AASAFailureCase(
            statusCode: 200,
            headers: Self.jsonHeaders,
            body: Data(#"{"applinks":{"apps":["PREFIX.com.ownid.passkey.diagnostics.tests"]}}"#.utf8),
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
            .http(statusCode: 200, headers: Self.jsonHeaders, body: Self.aasaData(apps: [Self.validAppEntry])),
            for: Self.cdnURL(for: domain)
        )
        let sink = PasskeyDiagnosticsLogSink()
        let diagnostics = Self.makeDiagnostics(logger: sink)

        diagnostics.verify(rpId: domain)

        let report = try await Self.waitForReport(in: sink)
        #expect(report.message.contains(testCase.expectedReportFragment))
        #expect(PasskeyDiagnosticsTestURLProtocol.requests(to: Self.aasaURL(for: domain)).count == 1)
    }

    @available(iOS 16.0, *)
    @Test func `Non HTTP origin response is reported as failure`() async throws {
        PasskeyDiagnosticsTestURLProtocol.reset()

        let domain = Self.uniqueDomain()
        PasskeyDiagnosticsTestURLProtocol.register(.nonHTTP(body: Data()), for: Self.aasaURL(for: domain))
        PasskeyDiagnosticsTestURLProtocol.register(
            .http(statusCode: 200, headers: Self.jsonHeaders, body: Self.aasaData(apps: [Self.validAppEntry])),
            for: Self.cdnURL(for: domain)
        )
        let sink = PasskeyDiagnosticsLogSink()
        let diagnostics = Self.makeDiagnostics(logger: sink)

        diagnostics.verify(rpId: domain)

        let report = try await Self.waitForReport(in: sink)
        #expect(report.message.contains("FAIL - Fetch AASA - Non-HTTP response"))
    }

    @available(iOS 16.0, *)
    @Test(arguments: [
        TransportFailureCase(code: .timedOut, expectedStatus: "WARN", description: "timeout"),
        TransportFailureCase(code: .notConnectedToInternet, expectedStatus: "WARN", description: "offline"),
        TransportFailureCase(code: .networkConnectionLost, expectedStatus: "WARN", description: "lost connection"),
        TransportFailureCase(code: .serverCertificateUntrusted, expectedStatus: "FAIL", description: "certificate trust"),
    ])
    func `Transport failures use scoped warning and failure statuses`(_ testCase: TransportFailureCase) async throws {
        PasskeyDiagnosticsTestURLProtocol.reset()

        let domain = Self.uniqueDomain()
        PasskeyDiagnosticsTestURLProtocol.register(.failure(testCase.code), for: Self.aasaURL(for: domain))
        PasskeyDiagnosticsTestURLProtocol.register(.failure(testCase.code), for: Self.cdnURL(for: domain))
        let sink = PasskeyDiagnosticsLogSink()
        let diagnostics = Self.makeDiagnostics(logger: sink)

        diagnostics.verify(rpId: domain)

        let report = try await Self.waitForReport(in: sink)
        #expect(report.message.contains("\(testCase.expectedStatus) - Fetch AASA"))
        #expect(report.message.contains("\(testCase.expectedStatus) - Apple CDN"))
    }

    @available(iOS 16.0, *)
    @Test(arguments: [
        CDNBodyFailureCase(body: Data("not-json".utf8), expectedReason: "JSON parse error"),
        CDNBodyFailureCase(
            body: Data(#"{"domain":{"apps":["PREFIX.com.ownid.passkey.diagnostics.tests"]}}"#.utf8),
            expectedReason: "webcredentials.apps missing"
        ),
    ])
    func `Malformed CDN responses are reported without accepting nested apps`(_ testCase: CDNBodyFailureCase) async throws {
        PasskeyDiagnosticsTestURLProtocol.reset()

        let domain = Self.uniqueDomain()
        PasskeyDiagnosticsTestURLProtocol.register(
            .http(statusCode: 200, headers: Self.jsonHeaders, body: Self.aasaData(apps: [Self.validAppEntry])),
            for: Self.aasaURL(for: domain)
        )
        PasskeyDiagnosticsTestURLProtocol.register(
            .http(statusCode: 200, headers: Self.jsonHeaders, body: testCase.body),
            for: Self.cdnURL(for: domain)
        )
        let sink = PasskeyDiagnosticsLogSink()
        let diagnostics = Self.makeDiagnostics(logger: sink)

        diagnostics.verify(rpId: domain)

        let report = try await Self.waitForReport(in: sink)
        #expect(report.message.contains("FAIL - Apple CDN - \(testCase.expectedReason)"))
        #expect(PasskeyDiagnosticsTestURLProtocol.requests(to: Self.cdnURL(for: domain)).count == 1)
    }

    @available(iOS 16.0, *)
    @Test func `CDN HTTP failure reports Apple diagnostic headers`() async throws {
        PasskeyDiagnosticsTestURLProtocol.reset()

        let domain = Self.uniqueDomain()
        PasskeyDiagnosticsTestURLProtocol.register(
            .http(statusCode: 200, headers: Self.jsonHeaders, body: Self.aasaData(apps: [Self.validAppEntry])),
            for: Self.aasaURL(for: domain)
        )
        PasskeyDiagnosticsTestURLProtocol.register(
            .http(
                statusCode: 404,
                headers: [
                    "Apple-Failure-Reason": "SWCERR00101 Bad HTTP Response",
                    "Apple-Failure-Details": "status 404",
                    "Apple-From": "origin",
                ],
                body: Data()
            ),
            for: Self.cdnURL(for: domain)
        )
        let sink = PasskeyDiagnosticsLogSink()
        let diagnostics = Self.makeDiagnostics(logger: sink)

        diagnostics.verify(rpId: domain)

        let report = try await Self.waitForReport(in: sink)
        #expect(report.message.contains("FAIL - Apple CDN - HTTP 404"))
        #expect(report.message.contains("Apple-Failure-Reason=SWCERR00101 Bad HTTP Response"))
        #expect(report.message.contains("Apple-Failure-Details=status 404"))
        #expect(report.message.contains("Apple-From=origin"))
    }

    private static let bundleID = PasskeyDiagnosticsLocalInfo.bundleIdentifier
    private static let validAppEntry = "PREFIX.\(bundleID)"
    private static let jsonHeaders = ["Content-Type": "application/json"]

    @available(iOS 16.0, *)
    private static func makeDiagnostics(logger: PasskeyDiagnosticsLogSink) -> PasskeyDiagnosticsImpl {
        let router = OwnIDLogRouter(ownIDLoggerProvider: { logger }, serverLoggerProvider: { nil })
        return PasskeyDiagnosticsImpl(
            localInfo: PasskeyDiagnosticsLocalInfo(),
            logger: router,
            sessionFactory: { configuration, delegate in
                configuration.protocolClasses = [PasskeyDiagnosticsTestURLProtocol.self]
                return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
            }
        )
    }

    private static func registerAASAAndCDN(for domain: String, originApps: [String], cdnApps: [String]) {
        PasskeyDiagnosticsTestURLProtocol.register(
            .http(statusCode: 200, headers: jsonHeaders, body: aasaData(apps: originApps)),
            for: aasaURL(for: domain)
        )
        PasskeyDiagnosticsTestURLProtocol.register(
            .http(statusCode: 200, headers: jsonHeaders, body: aasaData(apps: cdnApps)),
            for: cdnURL(for: domain)
        )
    }

    private static func aasaData(apps: [String]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["webcredentials": ["apps": apps]])
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

struct BundleCandidateFailureCase: Sendable, CustomTestStringConvertible {
    let appEntry: String
    let description: String

    var testDescription: String { description }
}

struct TransportFailureCase: Sendable, CustomTestStringConvertible {
    let code: URLError.Code
    let expectedStatus: String
    let description: String

    var testDescription: String { description }
}

struct CDNBodyFailureCase: Sendable, CustomTestStringConvertible {
    let body: Data
    let expectedReason: String

    var testDescription: String { expectedReason }
}

private struct PasskeyDiagnosticsLocalInfo: LocalInfo {
    static let bundleIdentifier = "com.ownid.passkey.diagnostics.tests"

    let modules: [(name: String, version: String)] = [("OwnIDCore", "0.0.0")]
    let bundleID = Self.bundleIdentifier
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
    case nonHTTP(body: Data)
    case failure(URLError.Code)
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
        case .nonHTTP(let body):
            let response = URLResponse(
                url: url,
                mimeType: "application/json",
                expectedContentLength: body.count,
                textEncodingName: "utf-8"
            )
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
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
