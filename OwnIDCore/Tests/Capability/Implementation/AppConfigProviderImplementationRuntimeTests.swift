import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

// Covers: CACHE-RUNTIME-010, CACHE-RUNTIME-020, CACHE-RUNTIME-030, CACHE-RUNTIME-050, CACHE-RUNTIME-070, CFG-RUNTIME-130
@Suite(.serialized)
struct AppConfigProviderImplementationRuntimeTests {

    @Test func `Startup success emits fresh config persists cache updates login ID config and cancels monitor`() async throws {
        let harness = try Self.makeHarness(
            network: ScriptedAppConfigNetwork([
                .success(Self.remoteConfigBody(displayName: "Fresh Config", logLevel: "Debug"))
            ])
        )
        defer { harness.cleanup() }

        let config = try await harness.provider.getOrFetchConfig()
        let streamedConfig = try await Self.nextConfig(from: harness.provider.configStream)

        #expect(config.displayName == "Fresh Config")
        #expect(streamedConfig == config)
        #expect(harness.loginIDConfiguration.configuration.supportedTypes == [.email, .phoneNumber])
        #expect(harness.loginIDConfiguration.configuration.validationRegexes[.email] != nil)
        #expect(try Self.cachedConfig(at: harness.cacheFileURL) == config)
        #expect(await harness.provider.isNetworkMonitoringActiveForTest() == false)
        #expect(await harness.network.requestCount == 1)
    }

    @Test func `Cache write failure keeps fresh config active and logs persistence failure`() async throws {
        let logs = LogCapture()
        let harness = try Self.makeHarness(
            network: ScriptedAppConfigNetwork([
                .success(Self.remoteConfigBody(displayName: "Uncached Fresh Config", logLevel: "Warning"))
            ]),
            logger: testLogRouter(sink: logs, category: "AppConfigProviderTests")
        )
        defer { harness.cleanup() }
        try FileManager.default.createDirectory(at: harness.cacheFileURL, withIntermediateDirectories: true)

        let config = try await harness.provider.getOrFetchConfig()
        let streamedConfig = try await Self.nextConfig(from: harness.provider.configStream)

        #expect(config.displayName == "Uncached Fresh Config")
        #expect(streamedConfig == config)
        #expect(harness.loginIDConfiguration.configuration.supportedTypes == [.email, .phoneNumber])
        #expect(Self.isDirectory(harness.cacheFileURL))
        #expect(
            logs.entries.contains {
                $0.level == .warn && $0.message == "Failed to persist app config" && $0.hasCause
            }
        )
        #expect(await harness.provider.isNetworkMonitoringActiveForTest() == false)
        #expect(await harness.network.requestCount == 1)
    }

    @Test func `Bootstrap timeout emits stored config when startup fetch is unavailable`() async throws {
        let storedConfig = Self.appConfig(displayName: "Stored Config", supportedTypes: [.userName], logLevel: .information)
        let network = ScriptedAppConfigNetwork([.stallUntilResolved])
        let harness = try Self.makeHarness(network: network, bootstrapTimeoutNanoseconds: 0)
        defer { harness.cleanup() }
        try Self.writeCache(storedConfig, to: harness.cacheFileURL)

        let config = try await harness.provider.getOrFetchConfig()

        #expect(config == storedConfig)
        #expect(harness.loginIDConfiguration.configuration.supportedTypes == [.userName])
        #expect(await harness.provider.isNetworkMonitoringActiveForTest() == true)
    }

    @Test func `Bootstrap timeout emits default config and deletes corrupted cache`() async throws {
        let network = ScriptedAppConfigNetwork([.stallUntilResolved])
        let harness = try Self.makeHarness(network: network, bootstrapTimeoutNanoseconds: 0)
        defer { harness.cleanup() }
        try FileManager.default.createDirectory(at: harness.cacheFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not valid app config json".utf8).write(to: harness.cacheFileURL)

        let config = try await harness.provider.getOrFetchConfig()

        #expect(config == .default)
        #expect(FileManager.default.fileExists(atPath: harness.cacheFileURL.path) == false)
        #expect(harness.loginIDConfiguration.configuration.supportedTypes == LoginIDConfiguration.default.supportedTypes)
        try await withTestTimeout("startup request after corrupted cache fallback") {
            await network.waitForRequestCount(1)
        }
        #expect(await network.requestCount == 1)
    }

    @Test func `Decode failure falls back and schedules deterministic retry`() async throws {
        let network = ScriptedAppConfigNetwork([
            .success(#"{"displayName":"missing loginIdConfig"}"#),
            .stallUntilResolved,
        ])
        let harness = try Self.makeHarness(network: network, retryScheduleSeconds: [0])
        defer { harness.cleanup() }
        var iterator = harness.provider.configStream.makeAsyncIterator()

        let initialConfig = try await harness.provider.getOrFetchConfig()
        #expect(try #require(await iterator.next()) == initialConfig)
        try await withTestTimeout("retry request") {
            await network.waitForRequestCount(2)
        }
        await network.resolveNextStall(with: .success(Self.remoteConfigBody(displayName: "Retried Config", logLevel: "Information")))
        let retriedConfig = try #require(await iterator.next())

        #expect(initialConfig == .default)
        #expect(retriedConfig.displayName == "Retried Config")
        #expect(try Self.cachedConfig(at: harness.cacheFileURL) == retriedConfig)
        #expect(await harness.provider.isNetworkMonitoringActiveForTest() == false)
    }

    @Test func `Network failure falls back and schedules deterministic retry`() async throws {
        let failureURL = try #require(URL(string: "https://app-config-runtime.ownid.test/direct-network-failure"))
        let network = ScriptedAppConfigNetwork([
            .failure(.networkError(NetworkResponse.Fail.NetworkError(url: failureURL, error: URLError(.notConnectedToInternet)))),
            .stallUntilResolved,
        ])
        let harness = try Self.makeHarness(network: network, retryScheduleSeconds: [0])
        defer { harness.cleanup() }
        var iterator = harness.provider.configStream.makeAsyncIterator()

        let initialConfig = try await harness.provider.getOrFetchConfig()
        #expect(try #require(await iterator.next()) == initialConfig)
        #expect(initialConfig == .default)
        #expect(harness.loginIDConfiguration.configuration.supportedTypes == LoginIDConfiguration.default.supportedTypes)

        try await withTestTimeout("network failure retry request") {
            await network.waitForRequestCount(2)
        }
        await network.resolveNextStall(
            with: .success(Self.remoteConfigBody(displayName: "Retried Network Config", logLevel: "Information"))
        )
        let retriedConfig = try #require(await iterator.next())

        #expect(retriedConfig.displayName == "Retried Network Config")
        #expect(harness.loginIDConfiguration.configuration.supportedTypes == [.email, .phoneNumber])
        #expect(try Self.cachedConfig(at: harness.cacheFileURL) == retriedConfig)
        #expect(await harness.provider.isNetworkMonitoringActiveForTest() == false)
        #expect(await harness.network.requestCount == 2)
    }

    @Test func `Concurrent bootstrap callers share one in-flight startup attempt`() async throws {
        let network = ScriptedAppConfigNetwork([.stallUntilResolved])
        let harness = try Self.makeHarness(network: network)
        defer { harness.cleanup() }

        let first = Task { try await harness.provider.getOrFetchConfig() }
        try await withTestTimeout("first app config request") {
            await network.waitForRequestCount(1)
        }

        let second = Task { try await harness.provider.getOrFetchConfig() }
        for _ in 0..<10 { await Task.yield() }

        #expect(await network.requestCount == 1)

        await network.resolveNextStall(with: .success(Self.remoteConfigBody(displayName: "Shared Config", logLevel: "Warning")))

        #expect(try await first.value.displayName == "Shared Config")
        #expect(try await second.value.displayName == "Shared Config")
        #expect(await network.requestCount == 1)
    }

    @Test func `Instance task-scope shutdown cancels active network monitor`() async throws {
        let failureURL = try #require(URL(string: "https://app-config-runtime.ownid.test/shutdown-network-monitor"))
        let monitor = RecordingAppConfigPathMonitor()
        let harness = try Self.makeHarness(
            network: ScriptedAppConfigNetwork([
                .failure(.networkError(NetworkResponse.Fail.NetworkError(url: failureURL, error: URLError(.notConnectedToInternet))))
            ]),
            bootstrapTimeoutNanoseconds: 0,
            retryScheduleSeconds: [300],
            pathMonitorFactory: { monitor }
        )
        defer { harness.cleanup() }

        let config = try await harness.provider.getOrFetchConfig()
        #expect(config == .default)
        try await withTestTimeout("app config monitor start") {
            await monitor.waitForStart()
        }
        #expect(await harness.provider.isNetworkMonitoringActiveForTest())

        harness.taskScope.shutdown()

        try await withTestTimeout("app config monitor cancel on shutdown") {
            await monitor.waitForCancelCount(1)
        }
        #expect(await harness.provider.isNetworkMonitoringActiveForTest() == false)
    }

    @Test func `AppConfig releases an externally supplied network without invalidating its app owned session`() async throws {
        let externalDelegate = AppConfigSessionInvalidationProbe()
        let externalSession = URLSession(configuration: .ephemeral, delegate: externalDelegate, delegateQueue: nil)
        let shutdownToken = ShutdownToken()
        let externalTaskScope = TaskScope(shutdownToken: shutdownToken)
        var externalNetwork: ExternalAppConfigNetwork? = ExternalAppConfigNetwork(session: externalSession)
        let externalNetworkReference = WeakReference(externalNetwork)
        var externalProvider: AppConfigProviderImpl? = try Self.makeSessionOwnershipProvider(
            taskScope: externalTaskScope,
            shutdownToken: shutdownToken,
            networkOverride: externalNetwork
        )
        let externalProviderReference = WeakReference(externalProvider)

        externalTaskScope.shutdown()
        externalTaskScope.shutdown()

        #expect(externalProviderReference.value != nil)
        #expect(externalNetworkReference.value != nil)
        #expect(externalDelegate.invalidationCount == 0)
        #expect((externalSession.delegate as AnyObject?) === externalDelegate)

        externalProvider = nil

        try await withTestTimeout("externally supplied AppConfig provider release") {
            while externalProviderReference.value != nil {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
        }
        #expect(externalProviderReference.value == nil)
        #expect(externalNetworkReference.value != nil)
        #expect(externalDelegate.invalidationCount == 0)
        #expect((externalSession.delegate as AnyObject?) === externalDelegate)

        externalNetwork = nil

        try await withTestTimeout("externally supplied AppConfig network release") {
            while externalNetworkReference.value != nil {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
        }
        #expect(externalNetworkReference.value == nil)
        #expect(externalDelegate.invalidationCount == 0)

        externalSession.invalidateAndCancel()
        try await externalDelegate.waitForInvalidation()
        #expect(externalDelegate.invalidationCount == 1)
    }

    private static func makeHarness(
        network: ScriptedAppConfigNetwork,
        logger: OwnIDLogRouter? = nil,
        bootstrapTimeoutNanoseconds: UInt64 = 2_000_000_000,
        retryScheduleSeconds: [UInt64] = [1, 2, 5, 10, 30, 60, 120, 300],
        pathMonitorFactory: (@Sendable () -> any AppConfigPathMonitoring)? = nil,
        sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
    ) throws -> AppConfigProviderRuntimeHarness {
        let appID = "Cache\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let rootURL = try #require(URL(string: "https://app-config-runtime.ownid.test/\(appID)"), sourceLocation: sourceLocation)
        let configuration = try OwnIDConfigurationImpl(appID: appID, env: .uat, region: .eu, rootURL: rootURL.absoluteString)
        let loginIDConfiguration = LoginIDConfigurationProviderImpl(initialConfiguration: .default)
        let shutdownToken = ShutdownToken()
        let taskScope = TaskScope(shutdownToken: shutdownToken)
        let cacheFileURL = Self.cacheFileURL(for: configuration)
        try? FileManager.default.removeItem(at: cacheFileURL)

        let provider: AppConfigProviderImpl
        if let pathMonitorFactory {
            provider = AppConfigProviderImpl(
                apiBaseURL: try APIBaseURLImpl(configuration: configuration),
                localInfo: AppConfigProviderLocalInfo(),
                languageTagsProvider: AppConfigProviderLanguageTagsProvider(),
                coder: JSONCoderImpl(),
                configuration: configuration,
                loginIdConfigurationProvider: loginIDConfiguration,
                taskScope: taskScope,
                shutdownToken: shutdownToken,
                logger: logger,
                interceptor: nil,
                networkOverride: network,
                startBackgroundWork: false,
                bootstrapTimeoutNanoseconds: bootstrapTimeoutNanoseconds,
                retryScheduleSeconds: retryScheduleSeconds,
                pathMonitorFactory: pathMonitorFactory
            )
        } else {
            provider = AppConfigProviderImpl(
                apiBaseURL: try APIBaseURLImpl(configuration: configuration),
                localInfo: AppConfigProviderLocalInfo(),
                languageTagsProvider: AppConfigProviderLanguageTagsProvider(),
                coder: JSONCoderImpl(),
                configuration: configuration,
                loginIdConfigurationProvider: loginIDConfiguration,
                taskScope: taskScope,
                shutdownToken: shutdownToken,
                logger: logger,
                interceptor: nil,
                networkOverride: network,
                startBackgroundWork: false,
                bootstrapTimeoutNanoseconds: bootstrapTimeoutNanoseconds,
                retryScheduleSeconds: retryScheduleSeconds
            )
        }

        return AppConfigProviderRuntimeHarness(
            provider: provider,
            network: network,
            loginIDConfiguration: loginIDConfiguration,
            taskScope: taskScope,
            cacheFileURL: cacheFileURL
        )
    }

    private static func makeSessionOwnershipProvider(
        taskScope: TaskScope,
        shutdownToken: ShutdownToken,
        networkOverride: (any NetworkProtocol)? = nil
    ) throws -> AppConfigProviderImpl {
        let appID = "SessionOwnership\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let configuration = try OwnIDConfigurationImpl(
            appID: appID,
            env: .uat,
            region: .eu,
            rootURL: "https://app-config-runtime.ownid.test/\(appID)"
        )
        return AppConfigProviderImpl(
            apiBaseURL: try APIBaseURLImpl(configuration: configuration),
            localInfo: AppConfigProviderLocalInfo(),
            languageTagsProvider: AppConfigProviderLanguageTagsProvider(),
            coder: JSONCoderImpl(),
            configuration: configuration,
            loginIdConfigurationProvider: nil,
            taskScope: taskScope,
            shutdownToken: shutdownToken,
            logger: nil,
            interceptor: nil,
            networkOverride: networkOverride,
            startBackgroundWork: false
        )
    }

    private static func appConfig(
        displayName: String,
        supportedTypes: [LoginIDType],
        logLevel: AppConfig.LogLevel
    ) -> AppConfig {
        AppConfig(
            loginIdConfig: supportedTypes.map { AppConfig.LoginIdConfig(type: $0, regex: nil) },
            displayName: displayName,
            webView: nil,
            ui: nil,
            logLevel: logLevel
        )
    }

    private static func remoteConfigBody(displayName: String, logLevel: String) -> String {
        """
        {
          "displayName": "\(displayName)",
          "loginIdConfig": [
            {"type": "Email", "regex": "^[^@]+@example\\\\.test$"},
            {"type": "PhoneNumber"}
          ],
          "logLevel": "\(logLevel)"
        }
        """
    }

    private static func cacheFileURL(for configuration: any OwnIDConfiguration) -> URL {
        let suffix = "\(configuration.env().rawValue.lowercased())_\(configuration.region.rawValue.lowercased())_\(configuration.appID)"
        let appSupportBase = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let directoryURL = (appSupportBase ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("com.ownid.sdk/config", isDirectory: true)
        return directoryURL.appendingPathComponent("appconfig_\(suffix).json")
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func writeCache(_ config: AppConfig, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let payload = try JSONCoderImpl().encodeToString(config)
        try Data(payload.utf8).write(to: url)
    }

    private static func cachedConfig(at url: URL) throws -> AppConfig {
        let data = try Data(contentsOf: url)
        let string = try #require(String(data: data, encoding: .utf8))
        return try JSONCoderImpl().decodeFromString(string, as: AppConfig.self)
    }

    private static func nextConfig(
        from stream: AsyncStream<AppConfig>,
        sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
    ) async throws -> AppConfig {
        try await withTestTimeout("app config stream") {
            var iterator = stream.makeAsyncIterator()
            return try #require(await iterator.next(), sourceLocation: sourceLocation)
        }
    }

}

private struct AppConfigProviderRuntimeHarness {
    let provider: AppConfigProviderImpl
    let network: ScriptedAppConfigNetwork
    let loginIDConfiguration: LoginIDConfigurationProviderImpl
    let taskScope: TaskScope
    let cacheFileURL: URL

    func cleanup() {
        taskScope.shutdown()
        try? FileManager.default.removeItem(at: cacheFileURL)
    }
}

private final class WeakReference<Value: AnyObject>: @unchecked Sendable {
    weak var value: Value?

    init(_ value: Value?) {
        self.value = value
    }
}

private final class AppConfigSessionInvalidationProbe: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private let invalidations = AsyncSignalRecorder<Void>()

    var invalidationCount: Int {
        lock.withLock { count }
    }

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: (any Error)?) {
        lock.withLock { count += 1 }
        invalidations.append(())
    }

    func waitForInvalidation() async throws {
        _ = try await invalidations.waitForFirst("external AppConfig session invalidation") { _ in true }
    }
}

private final class ExternalAppConfigNetwork: NetworkProtocol, @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession) {
        self.session = session
    }

    func run(_ request: NetworkRequest) async throws -> NetworkResponse {
        .fail(.networkError(.init(url: request.url, error: URLError(.notConnectedToInternet))))
    }
}

private final class RecordingAppConfigPathMonitor: AppConfigPathMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private var startCount = 0
    private var cancelCount = 0
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var cancelWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func start(queue: DispatchQueue, onAvailable: @escaping @Sendable () -> Void) {
        let waiters = lock.withLock {
            startCount += 1
            let waiters = startWaiters
            startWaiters.removeAll()
            return waiters
        }
        waiters.forEach { $0.resume() }
    }

    func cancel() {
        let waiters = lock.withLock {
            cancelCount += 1
            let ready = cancelWaiters.filter { cancelCount >= $0.0 }.map(\.1)
            cancelWaiters.removeAll { cancelCount >= $0.0 }
            return ready
        }
        waiters.forEach { $0.resume() }
    }

    func waitForStart() async {
        let shouldReturn = lock.withLock { startCount > 0 }
        if shouldReturn { return }
        await withCheckedContinuation { continuation in
            let shouldResume = lock.withLock {
                if startCount > 0 {
                    return true
                } else {
                    startWaiters.append(continuation)
                    return false
                }
            }
            if shouldResume { continuation.resume() }
        }
    }

    func waitForCancelCount(_ count: Int) async {
        let shouldReturn = lock.withLock { cancelCount >= count }
        if shouldReturn { return }
        await withCheckedContinuation { continuation in
            let shouldResume = lock.withLock {
                if cancelCount >= count {
                    return true
                } else {
                    cancelWaiters.append((count, continuation))
                    return false
                }
            }
            if shouldResume { continuation.resume() }
        }
    }
}

private enum ScriptedAppConfigNetworkRoute: Sendable {
    case success(String)
    case failure(NetworkResponse.Fail)
    case stallUntilResolved
}

private actor ScriptedAppConfigNetwork: NetworkProtocol {
    private var routes: [ScriptedAppConfigNetworkRoute]
    private var requests: [URLRequest] = []
    private var requestWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var stalledContinuationOrder: [UUID] = []
    private var stalledContinuations: [UUID: CheckedContinuation<NetworkResponse, any Error>] = [:]

    init(_ routes: [ScriptedAppConfigNetworkRoute]) {
        self.routes = routes
    }

    var requestCount: Int {
        requests.count
    }

    func run(_ request: NetworkRequest) async throws -> NetworkResponse {
        let urlRequest = request.buildURLRequest()
        requests.append(urlRequest)
        notifyRequestWaiters()

        let route = routes.isEmpty ? .failure(Self.networkFailure(for: urlRequest)) : routes.removeFirst()
        switch route {
        case .success(let body):
            return .success(
                NetworkResponse.Success(
                    url: urlRequest.url ?? URL(fileURLWithPath: "/missing-url"),
                    code: 200,
                    headers: [:],
                    body: body
                )
            )

        case .failure(let failure):
            return .fail(failure)

        case .stallUntilResolved:
            let stallID = UUID()
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    guard !Task.isCancelled else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    stalledContinuationOrder.append(stallID)
                    stalledContinuations[stallID] = continuation
                }
            } onCancel: {
                Task { await self.cancelStall(stallID) }
            }
        }
    }

    func waitForRequestCount(_ count: Int) async {
        if requests.count >= count { return }
        await withCheckedContinuation { continuation in
            requestWaiters.append((count, continuation))
        }
    }

    func resolveNextStall(with route: ScriptedAppConfigNetworkRoute) {
        guard let stallID = stalledContinuationOrder.first else { return }
        stalledContinuationOrder.removeFirst()
        guard let continuation = stalledContinuations.removeValue(forKey: stallID) else { return }
        switch route {
        case .success(let body):
            continuation.resume(
                returning: .success(
                    NetworkResponse.Success(
                        url: requests.last?.url ?? URL(fileURLWithPath: "/missing-url"),
                        code: 200,
                        headers: [:],
                        body: body
                    )
                )
            )

        case .failure(let failure):
            continuation.resume(returning: .fail(failure))

        case .stallUntilResolved:
            stalledContinuationOrder.insert(stallID, at: 0)
            stalledContinuations[stallID] = continuation
        }
    }

    private func cancelStall(_ stallID: UUID) {
        guard let continuation = stalledContinuations.removeValue(forKey: stallID) else { return }
        stalledContinuationOrder.removeAll { $0 == stallID }
        continuation.resume(throwing: CancellationError())
    }

    private func notifyRequestWaiters() {
        let ready = requestWaiters.filter { requests.count >= $0.0 }
        requestWaiters.removeAll { requests.count >= $0.0 }
        ready.forEach { $0.1.resume() }
    }

    private static func networkFailure(for request: URLRequest) -> NetworkResponse.Fail {
        .networkError(
            NetworkResponse.Fail.NetworkError(
                url: request.url ?? URL(fileURLWithPath: "/missing-url"),
                error: URLError(.notConnectedToInternet)
            )
        )
    }
}

private struct AppConfigProviderLocalInfo: LocalInfo {
    let modules: [(name: String, version: String)] = [("OwnIDCore", "0.0.0")]
    let bundleID = "com.ownid.tests"
    let appVersion = "1.0"
    let userAgent = "OwnIDAppConfigProviderTests/1.0"
    let correlationId = "app-config-correlation"
    let isDebuggable = true
    let isSystemFidoCapable = true
    let isDeviceSecured = true
    let isFaceHardwarePresent = false
    let isFingerprintHardwarePresent = false
    let isStrongBiometricEnabled = false
}

private struct AppConfigProviderLanguageTagsProvider: LanguageTagsProvider {
    func setLanguageTags(_ tags: [String]) {}

    var languageTags: AsyncStream<[LanguageTag]> {
        AsyncStream { continuation in
            continuation.yield([LanguageTag(language: "en", country: "US")])
            continuation.finish()
        }
    }
}
