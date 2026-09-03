import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

// Covers: DIAG-RUNTIME-010, DIAG-RUNTIME-020
@Suite(.serialized)
struct ServerLoggerRuntimeTests {

    @Test func `Production routers isolate two real instances and keep root diagnostics local`() async throws {
        try await withOwnIDRootStateTestLock {
            let firstName = InstanceName(value: "ServerLoggerRuntimeTests-A-\(UUID().uuidString)")
            let secondName = InstanceName(value: "ServerLoggerRuntimeTests-B-\(UUID().uuidString)")
            let firstRootURL = try #require(URL(string: "https://server-logger-runtime.ownid.test/production-a-\(UUID().uuidString)"))
            let secondRootURL = try #require(URL(string: "https://server-logger-runtime.ownid.test/production-b-\(UUID().uuidString)"))
            defer {
                OwnID.destroy(instanceName: firstName)
                OwnID.destroy(instanceName: secondName)
            }

            OwnID.initialize(instanceName: firstName) { configuration in
                configuration.appID = "DiagA\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
                configuration.rootURL = "https://127.0.0.1:9/production-a"
            }
            OwnID.initialize(instanceName: secondName) { configuration in
                configuration.appID = "DiagB\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
                configuration.rootURL = "https://127.0.0.1:9/production-b"
            }

            let firstContainer = try #require(OwnID.getInstanceContainer(firstName))
            let secondContainer = try #require(OwnID.getInstanceContainer(secondName))
            let firstHarness = try makeRoutedServerLoggerHarness(
                instanceName: firstName,
                rootURL: firstRootURL,
                taskScope: #require(firstContainer.getOrNil(type: TaskScope.self))
            )
            let secondHarness = try makeRoutedServerLoggerHarness(
                instanceName: secondName,
                rootURL: secondRootURL,
                taskScope: #require(secondContainer.getOrNil(type: TaskScope.self))
            )
            ServerLoggerTestURLProtocol.register(.http(statusCode: 202, body: "{}"), for: firstHarness.eventsURL)
            ServerLoggerTestURLProtocol.register(.http(statusCode: 202, body: "{}"), for: secondHarness.eventsURL)
            defer {
                ServerLoggerTestURLProtocol.unregister(firstHarness.eventsURL)
                ServerLoggerTestURLProtocol.unregister(secondHarness.eventsURL)
            }
            firstContainer.register(ServerLogger.self, instance: firstHarness.logger)
            secondContainer.register(ServerLogger.self, instance: secondHarness.logger)
            await firstHarness.enableDebug()
            await secondHarness.enableDebug()

            let firstRouter = try #require(firstContainer.getOrNil(type: OwnIDLogRouter.self))
            let secondRouter = try #require(secondContainer.getOrNil(type: OwnIDLogRouter.self))
            let rootRouter = try #require(OwnIDRootDIContainer.shared.getOrNil(type: OwnIDLogRouter.self))
            let rootMarker = "root-marker-\(UUID().uuidString)"
            let firstMarker = "first-marker-\(UUID().uuidString)"
            let secondMarker = "second-marker-\(UUID().uuidString)"

            rootRouter.logE(source: Self.self, prefix: "productionRouter", message: rootMarker)
            firstRouter.logE(source: Self.self, prefix: "productionRouter", message: firstMarker)
            secondRouter.logE(source: Self.self, prefix: "productionRouter", message: secondMarker)

            let firstRequest = try await withTestTimeout("first instance diagnostic") {
                try await ServerLoggerTestURLProtocol.waitForRequest(to: firstHarness.eventsURL) {
                    serverLoggerRequestBodyData($0).map { String(decoding: $0, as: UTF8.self).contains(firstMarker) } == true
                }
            }
            let secondRequest = try await withTestTimeout("second instance diagnostic") {
                try await ServerLoggerTestURLProtocol.waitForRequest(to: secondHarness.eventsURL) {
                    serverLoggerRequestBodyData($0).map { String(decoding: $0, as: UTF8.self).contains(secondMarker) } == true
                }
            }

            let firstPayload = try Self.payload(from: firstRequest)
            let secondPayload = try Self.payload(from: secondRequest)
            let allFirstBodies = ServerLoggerTestURLProtocol.requests(for: firstHarness.eventsURL).compactMap(serverLoggerRequestBodyData)
            let allSecondBodies = ServerLoggerTestURLProtocol.requests(for: secondHarness.eventsURL).compactMap(serverLoggerRequestBodyData)

            #expect(firstPayload["codeInitiator"] as? String == "[\(firstName.description)]ServerLoggerRuntimeTests:productionRouter")
            #expect(secondPayload["codeInitiator"] as? String == "[\(secondName.description)]ServerLoggerRuntimeTests:productionRouter")
            #expect(allFirstBodies.allSatisfy { !String(decoding: $0, as: UTF8.self).contains(secondMarker) })
            #expect(allSecondBodies.allSatisfy { !String(decoding: $0, as: UTF8.self).contains(firstMarker) })
            #expect((allFirstBodies + allSecondBodies).allSatisfy { !String(decoding: $0, as: UTF8.self).contains(rootMarker) })
        }
    }

    @Test func `Server logger waits for app config before posting diagnostics`() async throws {
        let harness = try Self.makeHarness(path: "waits-for-config")
        defer { harness.shutdown() }

        ServerLoggerTestURLProtocol.register(.http(statusCode: 202, body: #"{"accepted":true}"#), for: harness.eventsURL)
        defer { ServerLoggerTestURLProtocol.unregister(harness.eventsURL) }

        let logger = harness.makeLogger()
        try await withTestTimeout("server logger config fetch") {
            await harness.appConfigProvider.waitForFetch()
        }

        logger.log(level: .error, className: "Startup", message: "queued until config", cause: nil)
        #expect(ServerLoggerTestURLProtocol.requests(for: harness.eventsURL).isEmpty)

        await harness.appConfigProvider.resolve(Self.appConfig(logLevel: .warning))
        try await withTestTimeout("server logger request") {
            await ServerLoggerTestURLProtocol.waitForRequest(to: harness.eventsURL)
        }

        let request = try #require(ServerLoggerTestURLProtocol.requests(for: harness.eventsURL).first)
        let payload = try Self.payload(from: request)
        #expect(request.url == harness.eventsURL)
        #expect(payload["level"] as? String == "Error")
        #expect(payload["message"] as? String == "Startup => queued until config")
    }

    @Test func `Server logger filters by runtime threshold and posts enabled diagnostics`() async throws {
        let harness = try Self.makeHarness(path: "threshold-filter")
        defer { harness.shutdown() }

        ServerLoggerTestURLProtocol.register(.http(statusCode: 202, body: "{}"), for: harness.eventsURL)
        defer { ServerLoggerTestURLProtocol.unregister(harness.eventsURL) }

        let logger = harness.makeLogger()
        await harness.appConfigProvider.resolve(Self.appConfig(logLevel: .error))

        logger.log(level: .warn, className: "BelowThreshold", message: "not sent", cause: nil)
        logger.log(level: .error, className: "Enabled", message: "sent", cause: nil)

        try await withTestTimeout("server logger threshold request") {
            await ServerLoggerTestURLProtocol.waitForRequest(to: harness.eventsURL)
        }

        let requests = ServerLoggerTestURLProtocol.requests(for: harness.eventsURL)
        #expect(requests.count == 1)

        let payload = try Self.payload(from: try #require(requests.first))
        #expect(payload["level"] as? String == "Error")
        #expect(payload["codeInitiator"] as? String == "[\(harness.instanceName.description)]Enabled")
        #expect(payload["message"] as? String == "Enabled => sent")
    }

    @Test func `Server logger payload carries iOS diagnostics context`() async throws {
        let harness = try Self.makeHarness(path: "payload-context")
        defer { harness.shutdown() }

        ServerLoggerTestURLProtocol.register(.http(statusCode: 202, body: "{}"), for: harness.eventsURL)
        defer { ServerLoggerTestURLProtocol.unregister(harness.eventsURL) }

        let logger = harness.makeLogger()
        await harness.appConfigProvider.resolve(Self.appConfig(logLevel: .debug))

        let error = NSError(
            domain: "ServerLoggerRuntimeTests",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "provider failed"]
        )
        logger.log(level: .warn, className: "AuthFlow", message: "context captured", cause: error)

        try await withTestTimeout("server logger payload request") {
            await ServerLoggerTestURLProtocol.waitForRequest(to: harness.eventsURL)
        }

        let request = try #require(ServerLoggerTestURLProtocol.requests(for: harness.eventsURL).first)
        let payload = try Self.payload(from: request)
        let metadata = try #require(payload["metadata"] as? [String: Any])

        #expect(request.url == harness.eventsURL)
        #expect(payload["component"] as? String == "IosSdk")
        #expect(payload["level"] as? String == "Warning")
        #expect(payload["codeInitiator"] as? String == "[\(harness.instanceName.description)]AuthFlow")
        #expect(payload["message"] as? String == "AuthFlow => context captured")
        #expect(payload["exception"] as? String == "provider failed")
        #expect(payload["userAgent"] as? String == harness.localInfo.userAgent)
        #expect(payload["version"] as? String == harness.localInfo.appVersion)
        #expect(payload["sourceTimestamp"] as? String != nil)

        #expect(metadata["correlationId"] as? String == harness.localInfo.correlationId)
        #expect(metadata["bundleId"] as? String == harness.localInfo.bundleID)
        #expect(metadata["isUserVerifyingPlatformAuthenticatorAvailable"] as? Bool == true)
        #expect(metadata["isDeviceSecured"] as? Bool == true)
        #expect(metadata["isFingerprintHardwarePresent"] as? Bool == false)
        #expect(metadata["isFaceHardwarePresent"] as? Bool == true)
        #expect(metadata["isStrongBiometricEnabled"] as? Bool == true)
        #expect(metadata["previousRun"] == nil)
    }

    @Test func `Previous run metadata is attached only to its owning diagnostic`() async throws {
        let harness = try Self.makeHarness(path: "previous-run")
        defer { harness.shutdown() }

        ServerLoggerTestURLProtocol.register(.http(statusCode: 202, body: "{}"), for: harness.eventsURL)
        defer { ServerLoggerTestURLProtocol.unregister(harness.eventsURL) }

        let logger = harness.makeLogger()
        await harness.appConfigProvider.resolve(Self.appConfig(logLevel: .debug))
        logger.log(
            level: .warn,
            className: "RunDiagnostic",
            message: "Previous run observed",
            cause: nil,
            previousRun: PreviousRun(
                correlationId: "previous-correlation",
                processId: 4_242,
                exit: PreviousRun.Exit(
                    diagnosticType: "crash",
                    terminationReason: "namespace SIGNAL, code 0xb",
                    signal: 11,
                    exceptionType: 1,
                    exceptionCode: "0xdeadbeef"
                )
            )
        )

        try await withTestTimeout("server logger previous run request") {
            await ServerLoggerTestURLProtocol.waitForRequest(to: harness.eventsURL)
        }

        let request = try #require(ServerLoggerTestURLProtocol.requests(for: harness.eventsURL).first)
        let payload = try Self.payload(from: request)
        let metadata = try #require(payload["metadata"] as? [String: Any])
        let previousRun = try #require(metadata["previousRun"] as? [String: Any])
        let exit = try #require(previousRun["exit"] as? [String: Any])

        #expect(previousRun["correlationId"] as? String == "previous-correlation")
        #expect(previousRun["processId"] as? Int == 4_242)
        #expect(exit["diagnosticType"] as? String == "crash")
        #expect(exit["terminationReason"] as? String == "namespace SIGNAL, code 0xb")
        #expect(exit["signal"] as? Int == 11)
        #expect(exit["exceptionType"] as? Int == 1)
        #expect(exit["exceptionCode"] as? String == "0xdeadbeef")
    }

    @Test func `Server logger suppresses HTTP logging on diagnostics network requests`() async throws {
        let rootURL = try #require(URL(string: "https://server-logger-runtime.ownid.test/suppressed-\(UUID().uuidString)"))
        let configuration = try OwnIDConfigurationImpl(appID: "Diag123", env: .uat, region: .eu, rootURL: rootURL.absoluteString)
        let appConfigProvider = ScriptedAppConfigProvider()
        let network = RecordingServerLoggerNetwork()
        let taskScope = TaskScope(shutdownToken: ShutdownToken())
        defer { taskScope.shutdown() }
        let logger = ServerLogger(
            instanceName: InstanceName(value: "ServerLoggerRuntimeTests-\(UUID().uuidString)"),
            configuration: configuration,
            localInfo: ServerLoggerLocalInfo(),
            appConfigProvider: appConfigProvider,
            network: network,
            coder: JSONCoderImpl(),
            taskScope: taskScope
        )

        await appConfigProvider.resolve(Self.appConfig(logLevel: .debug))
        logger.log(level: .error, className: "Diagnostics", message: "suppress transport logging", cause: nil)

        let request = try await withTestTimeout("server logger recording network request") {
            await network.waitForRequest()
        }
        #expect(request.url == rootURL.appendingPathComponent("events"))
        #expect(request.suppressHttpLog)
    }

    private static func makeHarness(path: String) throws -> ServerLoggerRuntimeHarness {
        let rootURL = try #require(URL(string: "https://server-logger-runtime.ownid.test/\(path)-\(UUID().uuidString)"))
        let configuration = try OwnIDConfigurationImpl(appID: "Diag123", env: .uat, region: .eu, rootURL: rootURL.absoluteString)
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [ServerLoggerTestURLProtocol.self]
        let network = NetworkImpl(
            urlSession: URLSession(configuration: sessionConfiguration),
            shutdownToken: ShutdownToken(),
            retryConfig: nil,
            httpLogger: nil
        )
        let provider = ScriptedAppConfigProvider()
        let localInfo = ServerLoggerLocalInfo()
        let taskScope = TaskScope(shutdownToken: ShutdownToken())

        return ServerLoggerRuntimeHarness(
            instanceName: InstanceName(value: "ServerLoggerRuntimeTests-\(UUID().uuidString)"),
            configuration: configuration,
            localInfo: localInfo,
            appConfigProvider: provider,
            network: network,
            taskScope: taskScope,
            eventsURL: rootURL.appendingPathComponent("events")
        )
    }

    private static func appConfig(logLevel: AppConfig.LogLevel) -> AppConfig {
        AppConfig(
            loginIdConfig: AppConfig.default.loginIdConfig,
            displayName: nil,
            webView: nil,
            ui: nil,
            logLevel: logLevel
        )
    }

    private static func payload(from request: URLRequest) throws -> [String: Any] {
        let data = try #require(Self.bodyData(from: request), "Diagnostics request body is missing")
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any], "Diagnostics request body is not a JSON object")
    }

    private static func bodyData(from request: URLRequest) -> Data? {
        serverLoggerRequestBodyData(request)
    }

}

private actor RecordingServerLoggerNetwork: NetworkProtocol {
    private var requests: [NetworkRequest] = []
    private var waiters: [CheckedContinuation<NetworkRequest, Never>] = []

    func run(_ request: NetworkRequest) async throws -> NetworkResponse {
        requests.append(request)
        let waiters = waiters
        self.waiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: request)
        }
        return .success(.init(url: request.url, code: 202, headers: [:], body: "{}"))
    }

    func waitForRequest() async -> NetworkRequest {
        if let request = requests.first { return request }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

private struct ServerLoggerRuntimeHarness {
    let instanceName: InstanceName
    let configuration: any OwnIDConfiguration
    let localInfo: ServerLoggerLocalInfo
    let appConfigProvider: ScriptedAppConfigProvider
    let network: NetworkImpl
    let taskScope: TaskScope
    let eventsURL: URL

    func makeLogger() -> ServerLogger {
        ServerLogger(
            instanceName: instanceName,
            configuration: configuration,
            localInfo: localInfo,
            appConfigProvider: appConfigProvider,
            network: network,
            coder: JSONCoderImpl(),
            taskScope: taskScope
        )
    }

    func shutdown() {
        taskScope.shutdown()
    }
}

struct RoutedServerLoggerHarness {
    let logger: ServerLogger
    let eventsURL: URL
    private let appConfigProvider: ScriptedAppConfigProvider

    fileprivate init(logger: ServerLogger, eventsURL: URL, appConfigProvider: ScriptedAppConfigProvider) {
        self.logger = logger
        self.eventsURL = eventsURL
        self.appConfigProvider = appConfigProvider
    }

    func enableDebug() async {
        await appConfigProvider.resolve(
            AppConfig(
                loginIdConfig: AppConfig.default.loginIdConfig,
                displayName: nil,
                webView: nil,
                ui: nil,
                logLevel: .debug
            )
        )
    }
}

func makeRoutedServerLoggerHarness(
    instanceName: InstanceName,
    rootURL: URL,
    taskScope: TaskScope
) throws -> RoutedServerLoggerHarness {
    let configuration = try OwnIDConfigurationImpl(
        appID: "Diag\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))",
        env: .uat,
        region: .eu,
        rootURL: rootURL.absoluteString
    )
    let sessionConfiguration = URLSessionConfiguration.ephemeral
    sessionConfiguration.protocolClasses = [ServerLoggerTestURLProtocol.self]
    let network = NetworkImpl(
        urlSession: URLSession(configuration: sessionConfiguration),
        shutdownToken: ShutdownToken(),
        retryConfig: nil,
        httpLogger: nil
    )
    let appConfigProvider = ScriptedAppConfigProvider()
    let eventsURL = rootURL.appendingPathComponent("events")
    let logger = ServerLogger(
        instanceName: instanceName,
        configuration: configuration,
        localInfo: ServerLoggerLocalInfo(),
        appConfigProvider: appConfigProvider,
        network: network,
        coder: JSONCoderImpl(),
        taskScope: taskScope
    )
    return RoutedServerLoggerHarness(logger: logger, eventsURL: eventsURL, appConfigProvider: appConfigProvider)
}

private actor ScriptedAppConfigProvider: AppConfigProvider {
    private var current: AppConfig?
    private var fetchWaiters: [CheckedContinuation<Void, Never>] = []
    private var configWaiter: CheckedContinuation<AppConfig, any Error>?
    private var streamContinuations: [AsyncStream<AppConfig>.Continuation] = []

    nonisolated var configStream: AsyncStream<AppConfig> {
        AsyncStream { continuation in
            Task { await self.register(continuation) }
        }
    }

    func getOrFetchConfig() async throws -> AppConfig {
        notifyFetchWaiters()
        if let current { return current }
        return try await withCheckedThrowingContinuation { continuation in
            configWaiter = continuation
        }
    }

    func resolve(_ config: AppConfig) {
        current = config
        streamContinuations.forEach { $0.yield(config) }
        if let waiter = configWaiter {
            configWaiter = nil
            waiter.resume(returning: config)
        }
    }

    func waitForFetch() async {
        if configWaiter != nil { return }
        await withCheckedContinuation { continuation in
            fetchWaiters.append(continuation)
        }
    }

    private func register(_ continuation: AsyncStream<AppConfig>.Continuation) {
        streamContinuations.append(continuation)
        if let current {
            continuation.yield(current)
        }
    }

    private func notifyFetchWaiters() {
        let waiters = fetchWaiters
        fetchWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

private struct ServerLoggerLocalInfo: LocalInfo {
    let modules: [(name: String, version: String)] = [("OwnIDCore", "0.0.0")]
    let bundleID = "com.ownid.diagnostics.tests"
    let appVersion = "7.8.9"
    let userAgent = "OwnIDDiagnosticsTests/7.8.9"
    let correlationId = "diagnostics-correlation-id"
    let isDebuggable = true
    let isSystemFidoCapable = true
    let isDeviceSecured = true
    let isFaceHardwarePresent = true
    let isFingerprintHardwarePresent = false
    let isStrongBiometricEnabled = true
}

enum ServerLoggerTestURLProtocolRoute: Sendable {
    case http(statusCode: Int, body: String)
}

private final class ServerLoggerURLProtocolRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var routes: [URL: ServerLoggerTestURLProtocolRoute] = [:]
    private var requests: [URL: [URLRequest]] = [:]
    private var requestWaiters: [URL: [CheckedContinuation<Void, Never>]] = [:]

    func register(_ route: ServerLoggerTestURLProtocolRoute, for url: URL) {
        lock.lock()
        routes[url] = route
        requests[url] = []
        requestWaiters[url] = []
        lock.unlock()
    }

    func unregister(_ url: URL) {
        lock.lock()
        routes[url] = nil
        requests[url] = nil
        requestWaiters[url] = nil
        lock.unlock()
    }

    func hasRoute(for request: URLRequest) -> Bool {
        guard let url = request.url else { return false }
        lock.lock()
        let result = routes[url] != nil
        lock.unlock()
        return result
    }

    func start(_ request: URLRequest) -> ServerLoggerTestURLProtocolRoute? {
        guard let url = request.url else { return nil }

        lock.lock()
        requests[url, default: []].append(request)
        let waiters = requestWaiters.removeValue(forKey: url) ?? []
        let route = routes[url]
        lock.unlock()

        waiters.forEach { $0.resume() }
        return route
    }

    func requests(for url: URL) -> [URLRequest] {
        lock.lock()
        let result = requests[url] ?? []
        lock.unlock()
        return result
    }

    func waitForRequest(to url: URL) async {
        if hasRequest(to: url) { return }
        await withCheckedContinuation { continuation in
            if shouldResumeImmediatelyOrRegister(continuation, for: url) {
                continuation.resume()
            }
        }
    }

    private func hasRequest(to url: URL) -> Bool {
        lock.lock()
        let result = requests[url]?.isEmpty == false
        lock.unlock()
        return result
    }

    private func shouldResumeImmediatelyOrRegister(_ continuation: CheckedContinuation<Void, Never>, for url: URL) -> Bool {
        lock.lock()
        if requests[url]?.isEmpty == false {
            lock.unlock()
            return true
        }
        requestWaiters[url, default: []].append(continuation)
        lock.unlock()
        return false
    }
}

final class ServerLoggerTestURLProtocol: URLProtocol {
    private static let registry = ServerLoggerURLProtocolRegistry()

    static func register(_ route: ServerLoggerTestURLProtocolRoute, for url: URL) {
        registry.register(route, for: url)
    }

    static func unregister(_ url: URL) {
        registry.unregister(url)
    }

    static func requests(for url: URL) -> [URLRequest] {
        registry.requests(for: url)
    }

    static func waitForRequest(to url: URL) async {
        await registry.waitForRequest(to: url)
    }

    static func waitForRequest(
        to url: URL,
        where predicate: @escaping @Sendable (URLRequest) -> Bool
    ) async throws -> URLRequest {
        while true {
            if let request = requests(for: url).first(where: predicate) {
                return request
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
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
        case .http(let statusCode, let body):
            let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

func serverLoggerRequestBodyData(_ request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }

    stream.open()
    defer { stream.close() }

    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1024)
    while stream.hasBytesAvailable {
        let read = stream.read(&buffer, maxLength: buffer.count)
        if read <= 0 { break }
        data.append(buffer, count: read)
    }
    return data
}
