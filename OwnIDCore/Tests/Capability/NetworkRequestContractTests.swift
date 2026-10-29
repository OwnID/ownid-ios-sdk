import Foundation
import LocalAuthentication
import Testing

@testable import OwnIDCore

// Covers: CAP-020
struct NetworkRequestContractTests {

    @Test func `URL request builds default JSON POST metadata`() throws {
        let url = try #require(URL(string: "https://example.test/api/login"))
        var request = NetworkRequest(url: url)
        request.setBody(#"{"loginId":"user@example.com"}"#)

        let built = request.buildURLRequest()
        let body = try #require(built.httpBody)

        #expect(built.url == url)
        #expect(built.httpMethod == "POST")
        #expect(header(.accept, in: built) == "application/json")
        #expect(header(.cacheControl, in: built) == "no-store")
        #expect(header(.contentType, in: built) == "application/json; charset=utf-8")
        #expect(try #require(String(data: body, encoding: .utf8)) == #"{"loginId":"user@example.com"}"#)
    }

    @Test func `URL request respects explicit headers method caching and body shape`() throws {
        let url = try #require(URL(string: "https://example.test/api/config"))
        var request = NetworkRequest(url: url)
        request.setMethod(.get)
        request.setAllowCaching()
        request.setCachePolicy(.reloadIgnoringLocalCacheData)
        request.setHeader(name: NetworkRequest.Header.accept.rawValue, value: "application/problem+json")
        request.setHeader(name: NetworkRequest.Header.cacheControl.rawValue, value: "max-age=60")

        let built = request.buildURLRequest()

        #expect(built.url == url)
        #expect(built.httpMethod == "GET")
        #expect(built.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(header(.accept, in: built) == "application/problem+json")
        #expect(header(.cacheControl, in: built) == "max-age=60")
        #expect(header(.contentType, in: built) == nil)
        #expect(built.httpBody == nil)
    }

    @Test func `URL request adds bearer authorization from access token`() throws {
        let url = try #require(URL(string: "https://example.test/api/login"))
        var request = NetworkRequest(url: url)

        request.addToRequest(accessToken: AccessToken(token: "access-token"))

        let built = request.buildURLRequest()

        #expect(header(.authorization, in: built) == "Bearer access-token")
    }

    @Test func `URL request preserves existing trace header when setting absent value`() throws {
        let url = try #require(URL(string: "https://example.test/api/login"))
        var request = NetworkRequest(url: url)
        let existingTraceParent = "00-11111111111111111111111111111111-2222222222222222-01"

        request.setHeaderIfAbsent(name: NetworkRequest.Header.traceparent.rawValue, value: existingTraceParent)
        request.setHeaderIfAbsent(
            name: NetworkRequest.Header.traceparent.rawValue,
            value: "00-33333333333333333333333333333333-4444444444444444-00"
        )

        let built = request.buildURLRequest()

        #expect(header(.traceparent, in: built) == existingTraceParent)
    }

    @Test(arguments: [(true, true), (true, false), (false, true), (false, false)])
    func `Default header adapter adds only available metadata`(hasLocalInfo: Bool, hasLanguageProvider: Bool) async throws {
        let url = try #require(URL(string: "https://example.test/api/login"))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data(#"{"body":true}"#.utf8)
        request.setValue("tenant=value, other=two", forHTTPHeaderField: NetworkRequest.Header.baggage.rawValue)
        let adapter = NetworkRequest.DefaultHeadersAdapter(
            localInfo: hasLocalInfo ? StubLocalInfo(correlationId: "correlation-123") : nil,
            languageTagsProvider: hasLanguageProvider ? StaticLanguageTagsProvider(tags: [
                LanguageTag(language: "fr", country: "FR"),
                LanguageTag(language: "he", country: ""),
            ]) : nil,
            appURLHeaderValue: "App123.server.uat.ownid-eu.com"
        )

        let expectedLanguage = hasLanguageProvider ? "fr-FR,he" : nil
        let adapted = try await adapt(
            request,
            using: adapter,
            until: { header(.acceptLanguage, in: $0) == expectedLanguage }
        )

        #expect(adapted.url == url)
        #expect(adapted.httpMethod == "POST")
        #expect(adapted.httpBody == request.httpBody)
        #expect(header(.acceptLanguage, in: adapted) == expectedLanguage)
        #expect(header(.ownIDAppURL, in: adapted) == "App123.server.uat.ownid-eu.com")
        let expectedBaggage = hasLocalInfo
            ? "tenant=value,other=two,sdk.correlation_id=correlation-123"
            : "tenant=value, other=two"
        #expect(header(.baggage, in: adapted) == expectedBaggage)
    }

    @Test(arguments: [true, false])
    func `Default header adapter preserves existing singleton metadata`(hasMetadata: Bool) async throws {
        let url = try #require(URL(string: "https://example.test/api/login"))
        var request = URLRequest(url: url)
        request.setValue("de-DE", forHTTPHeaderField: NetworkRequest.Header.acceptLanguage.rawValue)
        request.setValue("custom.example.test", forHTTPHeaderField: NetworkRequest.Header.ownIDAppURL.rawValue)
        request.setValue("SDK.Correlation_ID=existing, tenant=value", forHTTPHeaderField: NetworkRequest.Header.baggage.rawValue)
        request.setValue("Host-App/2.0", forHTTPHeaderField: "User-Agent")
        let adapter = NetworkRequest.DefaultHeadersAdapter(
            localInfo: hasMetadata ? StubLocalInfo(correlationId: "new-correlation") : nil,
            languageTagsProvider: hasMetadata ? StaticLanguageTagsProvider(tags: [LanguageTag(language: "fr", country: "FR")]) : nil,
            appURLHeaderValue: "App123.server.ownid.com"
        )

        let adapted = try await adapt(request, using: adapter)

        #expect(header(.acceptLanguage, in: adapted) == "de-DE")
        #expect(header(.ownIDAppURL, in: adapted) == "custom.example.test")
        #expect(adapted.value(forHTTPHeaderField: "User-Agent") == "Host-App/2.0")
        let expectedBaggage = hasMetadata ? "SDK.Correlation_ID=existing,tenant=value" : "SDK.Correlation_ID=existing, tenant=value"
        #expect(header(.baggage, in: adapted) == expectedBaggage)
    }

    @Test func `Default header adapter observes language changes until released`() async throws {
        let url = try #require(URL(string: "https://example.test/api/login"))
        let request = URLRequest(url: url)
        let provider = LiveLanguageTagsProvider(tags: [LanguageTag(language: "fr", country: "FR")])
        defer { provider.finish() }
        var adapter: NetworkRequest.DefaultHeadersAdapter? = NetworkRequest.DefaultHeadersAdapter(
            localInfo: nil,
            languageTagsProvider: provider,
            appURLHeaderValue: "App123.server.ownid.com"
        )

        _ = try await adapt(request, using: #require(adapter), until: { header(.acceptLanguage, in: $0) == "fr-FR" })
        provider.setLanguageTags(["de", "ja"])
        let updated = try await adapt(request, using: #require(adapter), until: { header(.acceptLanguage, in: $0) == "de,ja" })
        #expect(header(.acceptLanguage, in: updated) == "de,ja")
        #expect(provider.terminations.entries.isEmpty)

        adapter = nil
        _ = try await provider.terminations.waitForFirst("Header adapter language subscription release") { _ in true }
    }

    private func adapt(
        _ request: URLRequest,
        using adapter: NetworkRequest.DefaultHeadersAdapter,
        until isReady: @escaping @Sendable (URLRequest) -> Bool = { _ in true }
    ) async throws -> URLRequest {
        try await withTestTimeout("Default headers adapter metadata") {
            while true {
                try Task.checkCancellation()
                let adapted = await adapter.adapt(request)
                if isReady(adapted) { return adapted }
                await Task.yield()
            }
        }
    }

    private func header(_ name: NetworkRequest.Header, in request: URLRequest) -> String? {
        request.value(forHTTPHeaderField: name.rawValue)
    }
}

private struct StaticLanguageTagsProvider: LanguageTagsProvider {
    let tags: [LanguageTag]

    func setLanguageTags(_ tags: [String]) {}

    var languageTags: AsyncStream<[LanguageTag]> {
        AsyncStream { continuation in
            continuation.yield(tags)
            continuation.finish()
        }
    }
}

private final class LiveLanguageTagsProvider: LanguageTagsProvider, Sendable {
    private let stream: AsyncStream<[LanguageTag]>
    private let continuation: AsyncStream<[LanguageTag]>.Continuation
    let terminations = AsyncSignalRecorder<Void>()

    init(tags: [LanguageTag]) {
        let (stream, continuation) = AsyncStream<[LanguageTag]>.makeStream()
        self.stream = stream
        self.continuation = continuation
        let terminations = self.terminations
        continuation.onTermination = { _ in terminations.append(()) }
        continuation.yield(tags)
    }

    var languageTags: AsyncStream<[LanguageTag]> { stream }

    func setLanguageTags(_ tags: [String]) {
        continuation.yield(tags.map { LanguageTag(language: $0, country: "") })
    }

    func finish() { continuation.finish() }
}

private struct StubLocalInfo: LocalInfo {
    let modules: [(name: String, version: String)] = []
    let bundleID = "com.ownid.tests"
    let appVersion = "1.0"
    let userAgent = "OwnIDTests/1.0"
    let correlationId: String
    let isDebuggable = true
    let isSystemFidoCapable = true
    let biometryType: LABiometryType = .none
    let isBiometryUsable = false
    let isBiometryEnrolled: Bool? = nil
    let isBiometryLockedOut: Bool? = nil
    let biometryLocalizedName: String? = nil
    let biometryIconSystemName: String? = nil
    let isPasscodeSet: Bool? = true
}
