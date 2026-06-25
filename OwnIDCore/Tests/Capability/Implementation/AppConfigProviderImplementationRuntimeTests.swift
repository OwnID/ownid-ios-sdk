import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

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

    private static func makeHarness(
        network: ScriptedAppConfigNetwork,
        logger: OwnIDLogRouter? = nil,
        bootstrapTimeoutNanoseconds: UInt64 = 2_000_000_000,
        retryScheduleSeconds: [UInt64] = [1, 2, 5, 10, 30, 60, 120, 300],
        sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
    ) throws -> AppConfigProviderRuntimeHarness {
        let appID = "Cache\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let rootURL = try #require(URL(string: "https://app-config-runtime.ownid.test/\(appID)"), sourceLocation: sourceLocation)
        let configuration = try OwnIDConfigurationImpl(appID: appID, env: .uat, region: .eu, rootURL: rootURL.absoluteString)
        let loginIDConfiguration = LoginIDConfigurationProviderImpl(initialConfiguration: .default)
        let taskScope = TaskScope(shutdownToken: ShutdownToken())
        let cacheFileURL = Self.cacheFileURL(for: configuration)
        try? FileManager.default.removeItem(at: cacheFileURL)

        let provider = AppConfigProviderImpl(
            apiBaseURL: try APIBaseURLImpl(configuration: configuration),
            localInfo: AppConfigProviderLocalInfo(),
            languageTagsProvider: AppConfigProviderLanguageTagsProvider(),
            coder: JSONCoderImpl(),
            configuration: configuration,
            loginIdConfigurationProvider: loginIDConfiguration,
            taskScope: taskScope,
            logger: logger,
            interceptor: nil,
            networkOverride: network,
            startBackgroundWork: false,
            bootstrapTimeoutNanoseconds: bootstrapTimeoutNanoseconds,
            retryScheduleSeconds: retryScheduleSeconds
        )

        return AppConfigProviderRuntimeHarness(
            provider: provider,
            network: network,
            loginIDConfiguration: loginIDConfiguration,
            taskScope: taskScope,
            cacheFileURL: cacheFileURL
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

private enum ScriptedAppConfigNetworkRoute: Sendable {
    case success(String)
    case failure(NetworkResponse.Fail)
    case stallUntilResolved
}

private actor ScriptedAppConfigNetwork: NetworkProtocol {
    private var routes: [ScriptedAppConfigNetworkRoute]
    private var requests: [URLRequest] = []
    private var requestWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var stalledContinuations: [CheckedContinuation<NetworkResponse, any Error>] = []

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
            return try await withCheckedThrowingContinuation { continuation in
                stalledContinuations.append(continuation)
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
        guard !stalledContinuations.isEmpty else { return }
        let continuation = stalledContinuations.removeFirst()
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
            stalledContinuations.insert(continuation, at: 0)
        }
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
