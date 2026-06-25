import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

struct ServerLocaleDataSourceProviderRuntimeTests {

    @Test func `Stale persisted locale remains visible while refresh is pending and updates after success`() async throws {
        let shutdownToken = ShutdownToken()
        defer { shutdownToken.cancel() }

        let appID = uniqueAppID()
        let configuration = try OwnIDConfigurationImpl(
            appID: appID,
            env: .uat,
            region: .us,
            rootURL: "https://locale.test/root"
        )
        let suffix = "\(configuration.env().rawValue)_\(configuration.appID)"
        let tag = LanguageTag(language: "fr", country: "CA")
        let cacheFileURLs = possibleCacheFileURLs(languageTag: tag, suffix: suffix)
        defer { cacheFileURLs.forEach { try? FileManager.default.removeItem(at: $0) } }

        let store = ServerLocaleDataStore(suffix: suffix, jsonCoder: JSONCoderImpl(), logger: nil)
        try await store.setContent(
            ServerLocaleContent(
                languageTag: tag,
                content: localeContent(skipPassword: "Old cached"),
                timeStamp: Date().timeIntervalSince1970 - 3_600
            ),
            for: tag
        )

        let network = GatedLocaleNetwork()
        let provider = ServerLocaleDataSourceProviderImpl(
            configuration: configuration,
            network: network,
            languageTagsProvider: StaticLocaleLanguageTagsProvider(tags: [tag]),
            jsonCoder: JSONCoderImpl(),
            taskScope: TaskScope(shutdownToken: shutdownToken),
            logger: nil
        )
        var iterator = provider.getDataSource(for: tag).makeAsyncIterator()

        let staleDataSource = try await requireNextDataSource(from: &iterator)
        #expect(staleDataSource.languageTag == tag)
        #expect(staleDataSource.getString(key: "widgets", "sbs-button", "skipPassword") == "Old cached")

        try await withTestTimeout("locale refresh request") {
            await network.waitForRequestCount(1)
        }
        #expect(await network.requestPaths() == ["/root/i18n/fr-CA/mobile-sdk.json"])
        let requestURL = try #require(await network.requestURL(at: 0))
        await network.send(
            .success(
                .init(
                    url: requestURL,
                    code: 200,
                    headers: [:],
                    body: #"{"widgets":{"sbs-button":{"skipPassword":"Fresh server","or":"or"}}}"#
                )
            )
        )

        let refreshedDataSource = try await requireNextDataSource(from: &iterator)
        #expect(refreshedDataSource.languageTag == tag)
        #expect(refreshedDataSource.getString(key: "widgets", "sbs-button", "skipPassword") == "Fresh server")

        let refreshedContent = try #require(await store.getContent(for: tag))
        #expect(refreshedContent.getString(localeKeys: ["widgets", "sbs-button", "skipPassword"]) == "Fresh server")
    }

    @Test func `Provider writes missing-locale placeholder with one-hour backoff after server 404`() async throws {
        let shutdownToken = ShutdownToken()
        defer { shutdownToken.cancel() }

        let appID = uniqueAppID()
        let configuration = try OwnIDConfigurationImpl(
            appID: appID,
            env: .uat,
            region: .us,
            rootURL: "https://locale.test/root"
        )
        let suffix = "\(configuration.env().rawValue)_\(configuration.appID)"
        let tag = LanguageTag(language: "es", country: "MX")
        let cacheFileURLs = possibleCacheFileURLs(languageTag: tag, suffix: suffix)
        defer { cacheFileURLs.forEach { try? FileManager.default.removeItem(at: $0) } }

        let network = GatedLocaleNetwork()
        let provider = makeProvider(configuration: configuration, tag: tag, network: network, shutdownToken: shutdownToken)
        var iterator = provider.getDataSource(for: tag).makeAsyncIterator()

        #expect(try await requireNextOptionalDataSource(from: &iterator) == nil)
        try await withTestTimeout("missing-locale request") {
            await network.waitForRequestCount(1)
        }
        let requestURL = try #require(await network.requestURL(at: 0))
        let beforeResponse = Date().timeIntervalSince1970
        await network.send(.fail(.httpError(.init(url: requestURL, statusCode: 404, headers: [:], body: ""))))
        try await withTestTimeout("missing-locale completion") {
            await network.waitForCompletionCount(1)
        }
        let afterResponse = Date().timeIntervalSince1970

        #expect(try await requireNextOptionalDataSource(from: &iterator) == nil)
        let store = ServerLocaleDataStore(suffix: suffix, jsonCoder: JSONCoderImpl(), logger: nil)
        let placeholder = try #require(await store.getContent(for: tag))
        #expect(placeholder.content == nil)
        #expect(placeholder.timeStamp >= beforeResponse)
        #expect(placeholder.timeStamp <= afterResponse)
        let backoffUntil = try #require(placeholder.backoffUntil)
        #expect(backoffUntil >= beforeResponse + 60 * 60)
        #expect(backoffUntil <= afterResponse + 60 * 60)
        #expect(!placeholder.isExpired())
    }

    @Test func `Network failure preserves cached locale content`() async throws {
        let shutdownToken = ShutdownToken()
        defer { shutdownToken.cancel() }

        let appID = uniqueAppID()
        let configuration = try OwnIDConfigurationImpl(
            appID: appID,
            env: .uat,
            region: .us,
            rootURL: "https://locale.test/root"
        )
        let suffix = "\(configuration.env().rawValue)_\(configuration.appID)"
        let tag = LanguageTag(language: "de", country: "DE")
        let cacheFileURLs = possibleCacheFileURLs(languageTag: tag, suffix: suffix)
        defer { cacheFileURLs.forEach { try? FileManager.default.removeItem(at: $0) } }

        let store = ServerLocaleDataStore(suffix: suffix, jsonCoder: JSONCoderImpl(), logger: nil)
        try await store.setContent(
            ServerLocaleContent(
                languageTag: tag,
                content: localeContent(skipPassword: "Cached before network failure"),
                timeStamp: Date().timeIntervalSince1970 - 3_600
            ),
            for: tag
        )

        let network = GatedLocaleNetwork()
        let provider = makeProvider(configuration: configuration, tag: tag, network: network, shutdownToken: shutdownToken)
        var iterator = provider.getDataSource(for: tag).makeAsyncIterator()

        let cachedDataSource = try await requireNextDataSource(from: &iterator)
        #expect(cachedDataSource.getString(key: "widgets", "sbs-button", "skipPassword") == "Cached before network failure")

        try await withTestTimeout("network-failure refresh request") {
            await network.waitForRequestCount(1)
        }
        let requestURL = try #require(await network.requestURL(at: 0))
        await network.send(.fail(.networkError(.init(url: requestURL, error: URLError(.notConnectedToInternet)))))
        try await withTestTimeout("network-failure refresh completion") {
            await network.waitForCompletionCount(1)
        }

        let persisted = try #require(await store.getContent(for: tag))
        #expect(persisted.content != nil)
        #expect(persisted.backoffUntil == nil)
        #expect(persisted.getString(localeKeys: ["widgets", "sbs-button", "skipPassword"]) == "Cached before network failure")
    }

    @Test func `Concurrent same-tag subscribers coalesce to one fetch and all observe update`() async throws {
        let shutdownToken = ShutdownToken()
        defer { shutdownToken.cancel() }

        let appID = uniqueAppID()
        let configuration = try OwnIDConfigurationImpl(
            appID: appID,
            env: .uat,
            region: .us,
            rootURL: "https://locale.test/root"
        )
        let suffix = "\(configuration.env().rawValue)_\(configuration.appID)"
        let tag = LanguageTag(language: "it", country: "IT")
        let cacheFileURLs = possibleCacheFileURLs(languageTag: tag, suffix: suffix)
        defer { cacheFileURLs.forEach { try? FileManager.default.removeItem(at: $0) } }

        let network = GatedLocaleNetwork()
        let provider = makeProvider(configuration: configuration, tag: tag, network: network, shutdownToken: shutdownToken)
        var firstIterator = provider.getDataSource(for: tag).makeAsyncIterator()
        var secondIterator = provider.getDataSource(for: tag).makeAsyncIterator()

        #expect(try await requireNextOptionalDataSource(from: &firstIterator) == nil)
        #expect(try await requireNextOptionalDataSource(from: &secondIterator) == nil)
        try await withTestTimeout("coalesced locale request") {
            await network.waitForRequestCount(1)
        }
        #expect(await network.requestPaths() == ["/root/i18n/it-IT/mobile-sdk.json"])

        let requestURL = try #require(await network.requestURL(at: 0))
        await network.send(
            .success(
                .init(
                    url: requestURL,
                    code: 200,
                    headers: [:],
                    body: #"{"widgets":{"sbs-button":{"skipPassword":"Ciao","or":"o"}}}"#
                )
            )
        )
        try await withTestTimeout("coalesced locale completion") {
            await network.waitForCompletionCount(1)
        }

        let firstUpdate = try await requireNextDataSource(from: &firstIterator)
        let secondUpdate = try await requireNextDataSource(from: &secondIterator)
        #expect(firstUpdate.getString(key: "widgets", "sbs-button", "skipPassword") == "Ciao")
        #expect(secondUpdate.getString(key: "widgets", "sbs-button", "skipPassword") == "Ciao")
        #expect(await network.requestPaths().count == 1)
    }
}

private final class StaticLocaleLanguageTagsProvider: LanguageTagsProvider, @unchecked Sendable {
    private let tags: [LanguageTag]

    init(tags: [LanguageTag]) {
        self.tags = tags
    }

    var languageTags: AsyncStream<[LanguageTag]> {
        AsyncStream { continuation in
            continuation.yield(tags)
        }
    }

    func setLanguageTags(_ tags: [String]) {}
}

private actor GatedLocaleNetwork: NetworkProtocol {
    private struct RequestCountWaiter {
        let minimumCount: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private var requests: [NetworkRequest] = []
    private var responses: [NetworkResponse] = []
    private var responseWaiters: [CheckedContinuation<NetworkResponse, any Error>] = []
    private var requestCountWaiters: [RequestCountWaiter] = []
    private var completionCount = 0
    private var completionCountWaiters: [RequestCountWaiter] = []

    func run(_ request: NetworkRequest) async throws -> NetworkResponse {
        requests.append(request)
        resumeReadyRequestCountWaiters()

        let response = try await withCheckedThrowingContinuation { continuation in
            if !responses.isEmpty {
                continuation.resume(returning: responses.removeFirst())
            } else {
                responseWaiters.append(continuation)
            }
        }
        completionCount += 1
        resumeReadyCompletionCountWaiters()
        return response
    }

    func send(_ response: NetworkResponse) {
        if responseWaiters.isEmpty {
            responses.append(response)
        } else {
            responseWaiters.removeFirst().resume(returning: response)
        }
    }

    func waitForRequestCount(_ count: Int) async {
        if requests.count >= count { return }

        await withCheckedContinuation { continuation in
            if requests.count >= count {
                continuation.resume()
            } else {
                requestCountWaiters.append(RequestCountWaiter(minimumCount: count, continuation: continuation))
            }
        }

        #expect(requests.count >= count)
    }

    func waitForCompletionCount(_ count: Int) async {
        if completionCount >= count { return }

        await withCheckedContinuation { continuation in
            if completionCount >= count {
                continuation.resume()
            } else {
                completionCountWaiters.append(RequestCountWaiter(minimumCount: count, continuation: continuation))
            }
        }

        #expect(completionCount >= count)
    }

    func requestURL(at index: Int) -> URL? {
        guard requests.indices.contains(index) else { return nil }
        return requests[index].url
    }

    func requestPaths() -> [String] {
        requests.map(\.url.path)
    }

    private func resumeReadyRequestCountWaiters() {
        let currentCount = requests.count
        let readyWaiters = requestCountWaiters.filter { currentCount >= $0.minimumCount }
        requestCountWaiters.removeAll { currentCount >= $0.minimumCount }
        for waiter in readyWaiters {
            waiter.continuation.resume()
        }
    }

    private func resumeReadyCompletionCountWaiters() {
        let currentCount = completionCount
        let readyWaiters = completionCountWaiters.filter { currentCount >= $0.minimumCount }
        completionCountWaiters.removeAll { currentCount >= $0.minimumCount }
        for waiter in readyWaiters {
            waiter.continuation.resume()
        }
    }
}

private func makeProvider(
    configuration: any OwnIDConfiguration,
    tag: LanguageTag,
    network: GatedLocaleNetwork,
    shutdownToken: ShutdownToken
) -> ServerLocaleDataSourceProviderImpl {
    ServerLocaleDataSourceProviderImpl(
        configuration: configuration,
        network: network,
        languageTagsProvider: StaticLocaleLanguageTagsProvider(tags: [tag]),
        jsonCoder: JSONCoderImpl(),
        taskScope: TaskScope(shutdownToken: shutdownToken),
        logger: nil
    )
}

private func requireNextDataSource(
    from iterator: inout AsyncStream<(any ServerLocaleDataSource)?>.AsyncIterator,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) async throws -> any ServerLocaleDataSource {
    let emission = try #require(await iterator.next(), sourceLocation: sourceLocation)
    return try #require(emission, sourceLocation: sourceLocation)
}

private func requireNextOptionalDataSource(
    from iterator: inout AsyncStream<(any ServerLocaleDataSource)?>.AsyncIterator,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) async throws -> (any ServerLocaleDataSource)? {
    try #require(await iterator.next(), sourceLocation: sourceLocation)
}

private func uniqueAppID() -> String {
    "App" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
}

private func possibleCacheFileURLs(languageTag: LanguageTag, suffix: String) -> [URL] {
    var baseURLs = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
    baseURLs.append(FileManager.default.temporaryDirectory)
    return baseURLs.map {
        $0.appendingPathComponent("com.ownid.sdk/locales/", isDirectory: true)
            .appendingPathComponent("\(languageTag.tagString)_\(suffix).json")
    }
}

private func localeContent(skipPassword: String, or: String = "or") -> [String: JSONValue] {
    [
        "widgets": .dictionary([
            "sbs-button": .dictionary([
                "skipPassword": .string(skipPassword),
                "or": .string(or),
            ])
        ])
    ]
}
