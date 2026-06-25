import Foundation
import Testing

@testable import OwnIDCore

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

    @Test func `Default header adapter adds language app URL and correlation metadata`() async throws {
        let url = try #require(URL(string: "https://example.test/api/login"))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data(#"{"body":true}"#.utf8)
        request.setValue("tenant=value, other=two", forHTTPHeaderField: NetworkRequest.Header.baggage.rawValue)
        let adapter = NetworkRequest.DefaultHeadersAdapter(
            localInfo: StubLocalInfo(correlationId: "correlation-123"),
            languageTagsProvider: StaticLanguageTagsProvider(tags: [
                LanguageTag(language: "fr", country: "FR"),
                LanguageTag(language: "he", country: ""),
            ]),
            appURLHeaderValue: "App123.server.uat.ownid-eu.com"
        )

        let adapted = try await adapt(
            request,
            using: adapter,
            until: { header(.acceptLanguage, in: $0) == "fr-FR,he" }
        )

        #expect(adapted.url == url)
        #expect(adapted.httpMethod == "POST")
        #expect(adapted.httpBody == request.httpBody)
        #expect(header(.acceptLanguage, in: adapted) == "fr-FR,he")
        #expect(header(.ownIDAppURL, in: adapted) == "App123.server.uat.ownid-eu.com")
        #expect(header(.baggage, in: adapted) == "tenant=value,other=two,sdk.correlation_id=correlation-123")
    }

    @Test func `Default header adapter preserves existing singleton metadata`() async throws {
        let url = try #require(URL(string: "https://example.test/api/login"))
        var request = URLRequest(url: url)
        request.setValue("de-DE", forHTTPHeaderField: NetworkRequest.Header.acceptLanguage.rawValue)
        request.setValue("custom.example.test", forHTTPHeaderField: NetworkRequest.Header.ownIDAppURL.rawValue)
        request.setValue("SDK.Correlation_ID=existing, tenant=value", forHTTPHeaderField: NetworkRequest.Header.baggage.rawValue)
        let adapter = NetworkRequest.DefaultHeadersAdapter(
            localInfo: StubLocalInfo(correlationId: "new-correlation"),
            languageTagsProvider: StaticLanguageTagsProvider(tags: [LanguageTag(language: "fr", country: "FR")]),
            appURLHeaderValue: "App123.server.ownid.com"
        )

        let adapted = try await adapt(request, using: adapter)

        #expect(header(.acceptLanguage, in: adapted) == "de-DE")
        #expect(header(.ownIDAppURL, in: adapted) == "custom.example.test")
        #expect(header(.baggage, in: adapted) == "SDK.Correlation_ID=existing,tenant=value")
    }

    private func adapt(
        _ request: URLRequest,
        using adapter: NetworkRequest.DefaultHeadersAdapter,
        until isReady: (URLRequest) -> Bool = { _ in true },
        sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
    ) async throws -> URLRequest {
        var adapted = await adapter.adapt(request)
        for _ in 0..<50 {
            if isReady(adapted) { return adapted }
            await Task.yield()
            adapted = await adapter.adapt(request)
        }
        return try #require(nil as URLRequest?, "Default headers adapter did not reach the expected state", sourceLocation: sourceLocation)
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

private struct StubLocalInfo: LocalInfo {
    let modules: [(name: String, version: String)] = []
    let bundleID = "com.ownid.tests"
    let appVersion = "1.0"
    let userAgent = "OwnIDTests/1.0"
    let correlationId: String
    let isDebuggable = true
    let isSystemFidoCapable = true
    let isDeviceSecured = true
    let isFaceHardwarePresent = false
    let isFingerprintHardwarePresent = false
    let isStrongBiometricEnabled = false
}
