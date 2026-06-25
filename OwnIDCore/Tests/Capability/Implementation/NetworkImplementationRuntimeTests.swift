import Foundation
import Testing

@testable import OwnIDCore

extension HTTPLogger: @unchecked Sendable {}

@Suite(.serialized)
struct NetworkImplementationRuntimeTests {

    @Test func `HTTP 2xx response maps to success`() async throws {
        let url = try Self.makeURL(path: "network/success")
        NetworkImplTestURLProtocol.register(
            .http(statusCode: 204, headers: ["X-OwnID-Test": "success"], body: #"{"ok":true}"#),
            for: url
        )
        defer { NetworkImplTestURLProtocol.unregister(url) }

        let response = try await makeNetwork().run(NetworkRequest(url: url))
        let success = try requireSuccess(response)

        #expect(success.url == url)
        #expect(success.code == 204)
        #expect(success.headers["X-OwnID-Test"] == "success")
        #expect(success.body == #"{"ok":true}"#)
    }

    @Test func `Non-2xx HTTP response maps to HTTP failure`() async throws {
        let url = try Self.makeURL(path: "network/http-failure")
        NetworkImplTestURLProtocol.register(
            .http(statusCode: 503, headers: ["Retry-After": "10"], body: #"{"error":"unavailable"}"#),
            for: url
        )
        defer { NetworkImplTestURLProtocol.unregister(url) }

        let response = try await makeNetwork().run(NetworkRequest(url: url))
        let failure = try requireFailure(response)
        guard case .httpError(let error) = failure else {
            Issue.record("Expected HTTP failure, got \(failure)")
            return
        }

        #expect(error.url == url)
        #expect(error.statusCode == 503)
        #expect(error.headers["Retry-After"] == "10")
        #expect(error.body == #"{"error":"unavailable"}"#)
    }

    @Test func `Non-HTTP response maps to response failure`() async throws {
        let url = try Self.makeURL(path: "network/non-http")
        NetworkImplTestURLProtocol.register(.nonHTTP(body: "not-http"), for: url)
        defer { NetworkImplTestURLProtocol.unregister(url) }

        let response = try await makeNetwork().run(NetworkRequest(url: url))
        let failure = try requireFailure(response)
        guard case .responseError(let error) = failure else {
            Issue.record("Expected response failure, got \(failure)")
            return
        }

        #expect(error.url == url)
        #expect(error.statusCode == nil)
        #expect((error.error as? URLError)?.code == .badServerResponse)
        #expect(error.headers.isEmpty)
        #expect(error.body == nil)
    }

    @Test func `Transport error maps to network failure`() async throws {
        let url = try Self.makeURL(path: "network/transport")
        NetworkImplTestURLProtocol.register(.fail(URLError(.notConnectedToInternet)), for: url)
        defer { NetworkImplTestURLProtocol.unregister(url) }

        let response = try await makeNetwork().run(NetworkRequest(url: url))
        let failure = try requireFailure(response)
        guard case .networkError(let error) = failure else {
            Issue.record("Expected network failure, got \(failure)")
            return
        }

        #expect(error.url == url)
        #expect(error.error.code == .notConnectedToInternet)
    }

    @Test func `Timeout maps to network failure`() async throws {
        let url = try Self.makeURL(path: "network/timeout")
        NetworkImplTestURLProtocol.register(.fail(URLError(.timedOut)), for: url)
        defer { NetworkImplTestURLProtocol.unregister(url) }

        let response = try await makeNetwork().run(NetworkRequest(url: url))
        let failure = try requireFailure(response)
        guard case .networkError(let error) = failure else {
            Issue.record("Expected timeout network failure, got \(failure)")
            return
        }

        #expect(error.url == url)
        #expect(error.error.code == .timedOut)
    }

    @Test func `Task cancellation remains cancellation`() async throws {
        let url = try Self.makeURL(path: "network/cancel")
        NetworkImplTestURLProtocol.register(.stallUntilCancelled, for: url)
        defer { NetworkImplTestURLProtocol.unregister(url) }

        let network = makeNetwork()
        let task = Task {
            try await network.run(NetworkRequest(url: url))
        }

        await NetworkImplTestURLProtocol.waitForStart(of: url)
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        await NetworkImplTestURLProtocol.waitForStop(of: url)
    }

    @Test func `Default headers are sent through URLSession transport`() async throws {
        let url = try Self.makeURL(path: "metadata/headers")
        NetworkImplTestURLProtocol.register(.http(statusCode: 200, headers: [:], body: "{}"), for: url)
        defer { NetworkImplTestURLProtocol.unregister(url) }

        let adapter = NetworkRequest.DefaultHeadersAdapter(
            localInfo: StubNetworkLocalInfo(correlationId: "correlation-123"),
            languageTagsProvider: StaticNetworkLanguageTagsProvider(tags: [
                LanguageTag(language: "fr", country: "FR"),
                LanguageTag(language: "he", country: ""),
            ]),
            appURLHeaderValue: "App123.server.uat.ownid-eu.com"
        )
        try await prime(adapter, untilAcceptLanguageIs: "fr-FR,he", url: url)

        let network = makeNetwork(
            requestAdapters: NetworkRequest.AdapterChain(adapters: [adapter]),
            additionalHeaders: ["User-Agent": "OwnIDTests/1.0"]
        )
        let traceParent = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
        var request = NetworkRequest(url: url)
        request.setHeader(name: NetworkRequest.Header.baggage.rawValue, value: "tenant=value")
        request.setHeader(name: NetworkRequest.Header.traceparent.rawValue, value: traceParent)

        _ = try await network.run(request)

        let sent = try #require(NetworkImplTestURLProtocol.requests(for: url).first)
        #expect(sent.url?.path.hasPrefix("/metadata/headers-") == true)
        #expect(sent.value(forHTTPHeaderField: "User-Agent") == "OwnIDTests/1.0")
        #expect(sent.value(forHTTPHeaderField: NetworkRequest.Header.acceptLanguage.rawValue) == "fr-FR,he")
        #expect(sent.value(forHTTPHeaderField: NetworkRequest.Header.ownIDAppURL.rawValue) == "App123.server.uat.ownid-eu.com")
        #expect(
            sent.value(forHTTPHeaderField: NetworkRequest.Header.baggage.rawValue)
                == "tenant=value,sdk.correlation_id=correlation-123"
        )

        let sentTraceParent = try #require(sent.value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue))
        #expect(sentTraceParent != traceParent)
        #expect(sentTraceParent.hasPrefix("00-4bf92f3577b34da6a3ce929d0e0e4736-"))
        #expect(sentTraceParent.hasSuffix("-01"))
        #expect(sentTraceParent.count == traceParent.count)
    }

    @Test func `Recoverable transport failure retries with preserved trace and correlation seed`() async throws {
        let url = try Self.makeURL(path: "retry/recoverable")
        NetworkImplTestURLProtocol.register(
            [
                .fail(URLError(.networkConnectionLost)),
                .http(statusCode: 200, headers: [:], body: #"{"retried":true}"#),
            ],
            for: url
        )
        defer { NetworkImplTestURLProtocol.unregister(url) }

        let adapter = NetworkRequest.DefaultHeadersAdapter(
            localInfo: StubNetworkLocalInfo(correlationId: "retry-correlation-123"),
            languageTagsProvider: StaticNetworkLanguageTagsProvider(tags: [LanguageTag(language: "en", country: "US")]),
            appURLHeaderValue: "App123.server.uat.ownid-eu.com"
        )
        try await prime(adapter, untilAcceptLanguageIs: "en-US", url: url)

        let network = makeNetwork(
            requestAdapters: NetworkRequest.AdapterChain(adapters: [adapter]),
            retryConfig: NetworkRequest.RetryConfig(retries: 1, initialDelayMilliseconds: 0, factor: 1.0, maxDelayMilliseconds: 0)
        )
        let traceParent = "00-4bf92f3577b34da6a3ce929d0e0e4736-1111111111111111-01"
        var request = NetworkRequest(url: url)
        request.setHeader(name: NetworkRequest.Header.baggage.rawValue, value: "tenant=value")
        request.setHeader(name: NetworkRequest.Header.traceparent.rawValue, value: traceParent)

        let response = try await network.run(request)
        let success = try requireSuccess(response)
        #expect(success.body == #"{"retried":true}"#)

        let sent = NetworkImplTestURLProtocol.requests(for: url)
        #expect(sent.count == 2)
        let sentTraceParentParts = try sent.map { request in
            #expect(
                request.value(forHTTPHeaderField: NetworkRequest.Header.baggage.rawValue)
                    == "tenant=value,sdk.correlation_id=retry-correlation-123"
            )
            let sentTraceParent = try #require(request.value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue))
            let parts = try traceParentParts(sentTraceParent)
            #expect(parts.version == "00")
            #expect(parts.traceID == "4bf92f3577b34da6a3ce929d0e0e4736")
            #expect(parts.flags == "01")
            #expect(parts.parentID.count == 16)
            return parts
        }
        #expect(sentTraceParentParts[0].parentID != sentTraceParentParts[1].parentID)
    }

    @Test func `Offline-like transport failure retries and recovers without platform text assertions`() async throws {
        let url = try Self.makeURL(path: "retry/offline-recoverable")
        NetworkImplTestURLProtocol.register(
            [
                .fail(URLError(.notConnectedToInternet)),
                .http(statusCode: 200, headers: [:], body: #"{"online":true}"#),
            ],
            for: url
        )
        defer { NetworkImplTestURLProtocol.unregister(url) }

        let network = makeNetwork(
            retryConfig: NetworkRequest.RetryConfig(retries: 1, initialDelayMilliseconds: 0, factor: 1.0, maxDelayMilliseconds: 0)
        )

        let response = try await network.run(NetworkRequest(url: url))
        let success = try requireSuccess(response)

        #expect(success.body == #"{"online":true}"#)
        #expect(NetworkImplTestURLProtocol.requests(for: url).count == 2)
    }

    @Test func `Cancellation during retry delay cancels operation before next URLProtocol load`() async throws {
        let url = try Self.makeURL(path: "retry/cancel-delay")
        NetworkImplTestURLProtocol.register(
            [
                .fail(URLError(.networkConnectionLost)),
                .http(statusCode: 200, headers: [:], body: #"{"shouldNotLoad":true}"#),
            ],
            for: url
        )
        defer { NetworkImplTestURLProtocol.unregister(url) }

        let retryDelay = NetworkImplRetryDelayProbe()
        let network = makeNetwork(
            retryConfig: NetworkRequest.RetryConfig(
                retries: 1,
                initialDelayMilliseconds: 10_000,
                factor: 1.0,
                maxDelayMilliseconds: 10_000
            ),
            retrySleeper: { try await retryDelay.sleep(nanoseconds: $0) }
        )
        let task = Task {
            try await network.run(NetworkRequest(url: url))
        }

        await retryDelay.waitForSleep()
        #expect(NetworkImplTestURLProtocol.requests(for: url).count == 1)

        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(retryDelay.sleepCalls() == [10_000_000_000])
        #expect(NetworkImplTestURLProtocol.requests(for: url).count == 1)
    }

    @Test func `Transport cancelled error remains task cancellation and is not retried`() async throws {
        let url = try Self.makeURL(path: "retry/cancelled-error")
        NetworkImplTestURLProtocol.register(.fail(URLError(.cancelled)), for: url)
        defer { NetworkImplTestURLProtocol.unregister(url) }

        let network = makeNetwork(
            retryConfig: NetworkRequest.RetryConfig(retries: 3, initialDelayMilliseconds: 0, factor: 1.0, maxDelayMilliseconds: 0)
        )

        await #expect(throws: CancellationError.self) {
            _ = try await network.run(NetworkRequest(url: url))
        }
        #expect(NetworkImplTestURLProtocol.requests(for: url).count == 1)
    }

    @Test func `Non-recoverable transport failure is not retried`() async throws {
        let url = try Self.makeURL(path: "retry/timeout")
        NetworkImplTestURLProtocol.register(.fail(URLError(.timedOut)), for: url)
        defer { NetworkImplTestURLProtocol.unregister(url) }

        let network = makeNetwork(
            retryConfig: NetworkRequest.RetryConfig(retries: 3, initialDelayMilliseconds: 0, factor: 1.0, maxDelayMilliseconds: 0)
        )

        let response = try await network.run(NetworkRequest(url: url))
        let failure = try requireFailure(response)
        guard case .networkError(let error) = failure else {
            Issue.record("Expected timeout network failure, got \(failure)")
            return
        }

        #expect(error.error.code == .timedOut)
        #expect(NetworkImplTestURLProtocol.requests(for: url).count == 1)
    }

    @Test func `HTTP failure is not retried`() async throws {
        let url = try Self.makeURL(path: "retry/http-failure")
        NetworkImplTestURLProtocol.register(.http(statusCode: 503, headers: [:], body: #"{"error":"unavailable"}"#), for: url)
        defer { NetworkImplTestURLProtocol.unregister(url) }

        let network = makeNetwork(
            retryConfig: NetworkRequest.RetryConfig(retries: 3, initialDelayMilliseconds: 0, factor: 1.0, maxDelayMilliseconds: 0)
        )

        let response = try await network.run(NetworkRequest(url: url))
        let failure = try requireFailure(response)
        guard case .httpError(let error) = failure else {
            Issue.record("Expected HTTP failure, got \(failure)")
            return
        }

        #expect(error.statusCode == 503)
        #expect(NetworkImplTestURLProtocol.requests(for: url).count == 1)
    }

    @Test func `HTTP logger records unsuppressed transport request and response`() async throws {
        let url = try Self.makeURL(path: "logging/unsuppressed")
        NetworkImplTestURLProtocol.register(.http(statusCode: 200, headers: ["X-Logged": "yes"], body: #"{"ok":true}"#), for: url)
        defer { NetworkImplTestURLProtocol.unregister(url) }
        let logs = LogCapture()
        let logger = CapturingOwnIDLogger(level: .verbose, category: "NetworkRuntimeTests", sink: logs)
        let network = makeNetwork(httpLogger: HTTPLogger(logger: logger))

        _ = try await network.run(NetworkRequest(url: url))

        #expect(NetworkImplTestURLProtocol.requests(for: url).count == 1)
        #expect(logs.entries.contains { $0.className == "HTTP" && $0.message.contains("--> POST \(url.absoluteString)") })
        #expect(logs.entries.contains { $0.className == "HTTP" && $0.message.contains("<-- 200 \(url.absoluteString)") })
        #expect(logs.messages.contains { $0.contains(#"{"ok":true}"#) })
    }

    @Test func `Suppressed HTTP logging still executes transport without local request or response logs`() async throws {
        let url = try Self.makeURL(path: "logging/suppressed")
        NetworkImplTestURLProtocol.register(.http(statusCode: 200, headers: [:], body: #"{"secret":true}"#), for: url)
        defer { NetworkImplTestURLProtocol.unregister(url) }
        let logs = LogCapture()
        let logger = CapturingOwnIDLogger(level: .verbose, category: "NetworkRuntimeTests", sink: logs)
        let network = makeNetwork(httpLogger: HTTPLogger(logger: logger))
        var request = NetworkRequest(url: url)
        request.setSuppressHttpLog()

        _ = try await network.run(request)

        #expect(NetworkImplTestURLProtocol.requests(for: url).count == 1)
        #expect(logs.entries.isEmpty)
    }

    private func makeNetwork(
        requestAdapters: NetworkRequest.AdapterChain? = nil,
        additionalHeaders: [String: String] = [:],
        retryConfig: NetworkRequest.RetryConfig? = nil,
        httpLogger: HTTPLogger? = nil,
        retrySleeper: NetworkImpl.RetrySleeper? = nil
    ) -> NetworkImpl {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NetworkImplTestURLProtocol.self]
        configuration.httpAdditionalHeaders = additionalHeaders
        if let retrySleeper {
            return NetworkImpl(
                urlSession: URLSession(configuration: configuration),
                requestAdapters: requestAdapters,
                retryConfig: retryConfig,
                httpLogger: httpLogger,
                retrySleeper: retrySleeper
            )
        } else {
            return NetworkImpl(
                urlSession: URLSession(configuration: configuration),
                requestAdapters: requestAdapters,
                retryConfig: retryConfig,
                httpLogger: httpLogger
            )
        }
    }

    private func requireSuccess(
        _ response: NetworkResponse,
        sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
    ) throws -> NetworkResponse.Success {
        guard case .success(let success) = response else {
            return try #require(nil as NetworkResponse.Success?, "Expected success, got \(response)", sourceLocation: sourceLocation)
        }
        return success
    }

    private func requireFailure(
        _ response: NetworkResponse,
        sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
    ) throws -> NetworkResponse.Fail {
        guard case .fail(let failure) = response else {
            return try #require(nil as NetworkResponse.Fail?, "Expected failure, got \(response)", sourceLocation: sourceLocation)
        }
        return failure
    }

    private func prime(
        _ adapter: NetworkRequest.DefaultHeadersAdapter,
        untilAcceptLanguageIs expected: String,
        url: URL,
        sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
    ) async throws {
        let request = URLRequest(url: url)
        for _ in 0..<50 {
            let adapted = await adapter.adapt(request)
            if adapted.value(forHTTPHeaderField: NetworkRequest.Header.acceptLanguage.rawValue) == expected {
                return
            }
            await Task.yield()
        }

        Issue.record("Default header adapter did not observe language tags", sourceLocation: sourceLocation)
    }

    private static func makeURL(path: String) throws -> URL {
        try #require(URL(string: "https://network-runtime.ownid.test/\(path)-\(UUID().uuidString)"))
    }

    private func traceParentParts(
        _ value: String,
        sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
    ) throws -> (version: String, traceID: String, parentID: String, flags: String) {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        try #require(parts.count == 4, "Expected a traceparent with four fields", sourceLocation: sourceLocation)
        return (parts[0], parts[1], parts[2], parts[3])
    }
}

private enum NetworkImplTestURLProtocolRoute: Sendable {
    case http(statusCode: Int, headers: [String: String], body: String)
    case nonHTTP(body: String)
    case fail(URLError)
    case stallUntilCancelled
}

// Synchronization is protected by `lock`; continuations are resumed outside the critical section.
private final class NetworkImplRetryDelayProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [UInt64] = []
    private var sleepWaiters: [CheckedContinuation<Void, Never>] = []
    private var sleepContinuation: CheckedContinuation<Void, any Error>?
    private var isCancelled = false

    func sleep(nanoseconds: UInt64) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let waiters: [CheckedContinuation<Void, Never>]

                lock.lock()
                calls.append(nanoseconds)
                if isCancelled {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                sleepContinuation = continuation
                waiters = sleepWaiters
                sleepWaiters.removeAll()
                lock.unlock()

                for waiter in waiters {
                    waiter.resume()
                }
            }
        } onCancel: {
            cancelSleep()
        }
    }

    func waitForSleep() async {
        if hasSleepCall() { return }

        await withCheckedContinuation { continuation in
            if shouldResumeImmediatelyOrRegisterSleepWaiter(continuation) {
                continuation.resume()
            }
        }
    }

    func sleepCalls() -> [UInt64] {
        lock.lock()
        let result = calls
        lock.unlock()
        return result
    }

    private func cancelSleep() {
        lock.lock()
        isCancelled = true
        let continuation = sleepContinuation
        sleepContinuation = nil
        lock.unlock()

        continuation?.resume(throwing: CancellationError())
    }

    private func hasSleepCall() -> Bool {
        lock.lock()
        let result = !calls.isEmpty
        lock.unlock()
        return result
    }

    private func shouldResumeImmediatelyOrRegisterSleepWaiter(
        _ continuation: CheckedContinuation<Void, Never>
    ) -> Bool {
        lock.lock()
        if !calls.isEmpty {
            lock.unlock()
            return true
        }
        sleepWaiters.append(continuation)
        lock.unlock()
        return false
    }
}

private final class NetworkImplURLProtocolRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var routes: [URL: [NetworkImplTestURLProtocolRoute]] = [:]
    private var requests: [URL: [URLRequest]] = [:]
    private var starts: [URL: Int] = [:]
    private var startWaiters: [URL: [CheckedContinuation<Void, Never>]] = [:]
    private var stops: [URL: Int] = [:]
    private var stopWaiters: [URL: [CheckedContinuation<Void, Never>]] = [:]

    func register(_ route: NetworkImplTestURLProtocolRoute, for url: URL) {
        register([route], for: url)
    }

    func register(_ scriptedRoutes: [NetworkImplTestURLProtocolRoute], for url: URL) {
        lock.lock()
        routes[url] = scriptedRoutes
        requests[url] = []
        starts[url] = 0
        startWaiters[url] = []
        stops[url] = 0
        stopWaiters[url] = []
        lock.unlock()
    }

    func unregister(_ url: URL) {
        lock.lock()
        routes[url] = nil
        requests[url] = nil
        starts[url] = nil
        startWaiters[url] = nil
        stops[url] = nil
        stopWaiters[url] = nil
        lock.unlock()
    }

    func hasRoute(for request: URLRequest) -> Bool {
        guard let url = request.url else { return false }
        lock.lock()
        let hasRoute = routes[url] != nil
        lock.unlock()
        return hasRoute
    }

    func start(_ request: URLRequest) -> NetworkImplTestURLProtocolRoute? {
        guard let url = request.url else { return nil }

        lock.lock()
        requests[url, default: []].append(request)
        starts[url, default: 0] += 1
        let waiters = startWaiters.removeValue(forKey: url) ?? []
        let route: NetworkImplTestURLProtocolRoute?
        if var scriptedRoutes = routes[url], !scriptedRoutes.isEmpty {
            route = scriptedRoutes[0]
            if scriptedRoutes.count > 1 {
                scriptedRoutes.removeFirst()
                routes[url] = scriptedRoutes
            }
        } else {
            route = nil
        }
        lock.unlock()

        for waiter in waiters {
            waiter.resume()
        }

        return route
    }

    func requests(for url: URL) -> [URLRequest] {
        lock.lock()
        let result = requests[url] ?? []
        lock.unlock()
        return result
    }

    func stop(_ request: URLRequest) {
        guard let url = request.url else { return }

        lock.lock()
        stops[url, default: 0] += 1
        let waiters = stopWaiters.removeValue(forKey: url) ?? []
        lock.unlock()

        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitForStart(of url: URL) async {
        if hasStarted(url) { return }

        await withCheckedContinuation { continuation in
            if shouldResumeImmediatelyOrRegisterStartWaiter(continuation, for: url) {
                continuation.resume()
            }
        }
    }

    func waitForStop(of url: URL) async {
        if hasStopped(url) { return }

        await withCheckedContinuation { continuation in
            if shouldResumeImmediatelyOrRegisterStopWaiter(continuation, for: url) {
                continuation.resume()
            }
        }
    }

    private func hasStarted(_ url: URL) -> Bool {
        lock.lock()
        let result = (starts[url] ?? 0) > 0
        lock.unlock()
        return result
    }

    private func hasStopped(_ url: URL) -> Bool {
        lock.lock()
        let result = (stops[url] ?? 0) > 0
        lock.unlock()
        return result
    }

    private func shouldResumeImmediatelyOrRegisterStartWaiter(
        _ continuation: CheckedContinuation<Void, Never>,
        for url: URL
    ) -> Bool {
        lock.lock()
        if (starts[url] ?? 0) > 0 {
            lock.unlock()
            return true
        }
        startWaiters[url, default: []].append(continuation)
        lock.unlock()
        return false
    }

    private func shouldResumeImmediatelyOrRegisterStopWaiter(
        _ continuation: CheckedContinuation<Void, Never>,
        for url: URL
    ) -> Bool {
        lock.lock()
        if (stops[url] ?? 0) > 0 {
            lock.unlock()
            return true
        }
        stopWaiters[url, default: []].append(continuation)
        lock.unlock()
        return false
    }
}

private final class NetworkImplTestURLProtocol: URLProtocol {
    private static let registry = NetworkImplURLProtocolRegistry()

    static func register(_ route: NetworkImplTestURLProtocolRoute, for url: URL) {
        registry.register(route, for: url)
    }

    static func register(_ routes: [NetworkImplTestURLProtocolRoute], for url: URL) {
        registry.register(routes, for: url)
    }

    static func unregister(_ url: URL) {
        registry.unregister(url)
    }

    static func requests(for url: URL) -> [URLRequest] {
        registry.requests(for: url)
    }

    static func waitForStart(of url: URL) async {
        await registry.waitForStart(of: url)
    }

    static func waitForStop(of url: URL) async {
        await registry.waitForStop(of: url)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        registry.hasRoute(for: request)
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
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)

        case .nonHTTP(let body):
            let response = URLResponse(
                url: url,
                mimeType: "text/plain",
                expectedContentLength: body.utf8.count,
                textEncodingName: "utf-8"
            )
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)

        case .fail(let error):
            client?.urlProtocol(self, didFailWithError: error)

        case .stallUntilCancelled:
            break
        }
    }

    override func stopLoading() {
        Self.registry.stop(request)
        client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
    }
}

private struct StaticNetworkLanguageTagsProvider: LanguageTagsProvider {
    let tags: [LanguageTag]

    func setLanguageTags(_ tags: [String]) {}

    var languageTags: AsyncStream<[LanguageTag]> {
        AsyncStream { continuation in
            continuation.yield(tags)
            continuation.finish()
        }
    }
}

private struct StubNetworkLocalInfo: LocalInfo {
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
