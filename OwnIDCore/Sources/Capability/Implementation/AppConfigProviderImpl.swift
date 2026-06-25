import Foundation
import Network

/// Instance-scoped ``AppConfigProvider`` implementation.
///
/// Applies the first usable app configuration for the instance: fresh remote configuration when available, otherwise
/// the stored configuration for the same app/environment, otherwise ``AppConfig/default``. Later successful remote
/// configuration replaces the active value and is stored for future startup fallback.
///
/// Remote, decoding, and persistence failures are logged and do not prevent a usable configuration from being emitted.
/// Corrupted stored configuration is ignored and removed before falling through to ``AppConfig/default``.
internal actor AppConfigProviderImpl: AppConfigProvider {
    private enum Trigger: String, Sendable {
        case startup = "STARTUP"
        case retryTimer = "RETRY_TIMER"
        case networkMonitor = "NETWORK_MONITOR"
    }

    private enum AttemptOutcome: Sendable {
        case success(AppConfig)
        case failure
    }

    private enum Event: Sendable {
        case start
        case bootstrapTimeout
        case retryTick
        case networkAvailable
        case attemptCompleted(trigger: Trigger, outcome: AttemptOutcome)
        case streamTerminated(UUID)
    }

    private let api: any AppConfigAPI
    private let loginIdConfigurationProvider: (any LoginIDConfigurationProvider)?
    private let taskScope: TaskScope
    private let logger: OwnIDLogRouter?
    private let cacheStore: CacheStore

    private var continuations: [UUID: AsyncStream<AppConfig>.Continuation] = [:]
    private var waiters: [UUID: CheckedContinuation<AppConfig, any Error>] = [:]

    private var pathMonitor: NWPathMonitor?
    private let pathMonitorQueue = DispatchQueue(label: "com.ownid.sdk.appconfig.network")

    private var started = false
    private var bootstrapCompleted = false
    private var inFlightAttempt = false
    private var retryEnabled = false
    private var stopConditionReached = false
    private var retryDelayIndex = 0

    private var current: AppConfig?
    private var bootstrapTimerTask: Task<Void, Never>?
    private var retryTimerTask: Task<Void, Never>?

    private let bootstrapTimeoutNanoseconds: UInt64
    private let retryScheduleSeconds: [UInt64]

    init(
        apiBaseURL: any APIBaseURL,
        localInfo: any LocalInfo,
        languageTagsProvider: any LanguageTagsProvider,
        coder: any JSONCoder,
        configuration: any OwnIDConfiguration,
        loginIdConfigurationProvider: (any LoginIDConfigurationProvider)?,
        taskScope: TaskScope,
        logger: OwnIDLogRouter?,
        interceptor: (any APICallInterceptor)?,
        networkOverride: (any NetworkProtocol)? = nil,
        startBackgroundWork: Bool = true,
        bootstrapTimeoutNanoseconds: UInt64 = 2_000_000_000,
        retryScheduleSeconds: [UInt64] = [1, 2, 5, 10, 30, 60, 120, 300]
    ) {
        let appConfigNetwork: any NetworkProtocol
        if let networkOverride {
            appConfigNetwork = networkOverride
        } else {
            let sessionConfiguration = URLSessionConfiguration.default
            sessionConfiguration.httpAdditionalHeaders = ["User-Agent": localInfo.userAgent]
            sessionConfiguration.tlsMinimumSupportedProtocolVersion = .TLSv12
            sessionConfiguration.timeoutIntervalForRequest = 5
            sessionConfiguration.timeoutIntervalForResource = 5

            appConfigNetwork = NetworkImpl(
                urlSession: URLSession(
                    configuration: sessionConfiguration,
                    delegate: NoRedirectDelegate(),
                    delegateQueue: nil
                ),
                requestAdapters: NetworkRequest.AdapterChain(adapters: [
                    NetworkRequest.DefaultHeadersAdapter(
                        localInfo: localInfo,
                        languageTagsProvider: languageTagsProvider,
                        appURLHeaderValue: configuration.appURLHeaderValue()
                    )
                ]),
                retryConfig: nil,
                httpLogger: nil
            )
        }

        self.api = AppConfigAPIImpl(apiBaseURL: apiBaseURL, network: appConfigNetwork, coder: coder, interceptor: interceptor)
        self.loginIdConfigurationProvider = loginIdConfigurationProvider
        self.taskScope = taskScope
        self.logger = logger
        self.cacheStore = CacheStore(configuration: configuration, coder: coder, logger: logger)
        self.bootstrapTimeoutNanoseconds = bootstrapTimeoutNanoseconds
        self.retryScheduleSeconds = retryScheduleSeconds

        if startBackgroundWork {
            _ = taskScope.spawn { [weak self] in
                await self?.startIfNeeded()
            }
        }
    }

    deinit {
        pathMonitor?.cancel()
        bootstrapTimerTask?.cancel()
        retryTimerTask?.cancel()
    }

    nonisolated internal var configStream: AsyncStream<AppConfig> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.register(continuation, id: id) }
        }
    }

    internal func getOrFetchConfig() async throws -> AppConfig {
        startIfNeeded()
        try Task.checkCancellation()
        if let current { return current }

        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if let current {
                    continuation.resume(returning: current)
                } else if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters[waiterID] = continuation
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(waiterID) }
        }
    }

    private func startIfNeeded() {
        guard !started else { return }
        started = true

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            _ = self?.taskScope.spawn { [weak self] in
                await self?.reduce(.networkAvailable)
            }
        }
        monitor.start(queue: pathMonitorQueue)
        pathMonitor = monitor

        bootstrapTimerTask?.cancel()
        bootstrapTimerTask = taskScope.spawn { [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.bootstrapTimeoutNanoseconds ?? 0)
            } catch {
                return
            }
            if Task.isCancelled { return }
            await self?.reduce(.bootstrapTimeout)
        }

        reduce(.start)
    }

    private func register(_ continuation: AsyncStream<AppConfig>.Continuation, id: UUID) {
        continuation.onTermination = { _ in
            Task { await self.reduce(.streamTerminated(id)) }
        }
        continuations[id] = continuation
        if let current {
            continuation.yield(current)
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let continuation = waiters.removeValue(forKey: id) else { return }
        continuation.resume(throwing: CancellationError())
    }

    private func reduce(_ event: Event) {
        switch event {
        case .streamTerminated(let id):
            continuations.removeValue(forKey: id)
            return

        case .start:
            launchAttemptIfPossible(trigger: .startup)

        case .bootstrapTimeout:
            guard !bootstrapCompleted else { break }
            bootstrapCompleted = true
            bootstrapTimerTask?.cancel()
            bootstrapTimerTask = nil
            if current == nil {
                _ = applyIfChanged(cacheStore.load() ?? .default)
            }
            if !stopConditionReached {
                retryEnabled = true
            }

        case .retryTick:
            retryTimerTask = nil
            launchAttemptIfPossible(trigger: .retryTimer)

        case .networkAvailable:
            launchAttemptIfPossible(trigger: .networkMonitor)

        case .attemptCompleted(let trigger, let outcome):
            inFlightAttempt = false

            switch outcome {
            case .success(let config):
                if !bootstrapCompleted {
                    bootstrapCompleted = true
                    bootstrapTimerTask?.cancel()
                    bootstrapTimerTask = nil
                }

                cacheStore.save(config)
                _ = applyIfChanged(config)

                if !stopConditionReached {
                    stopConditionReached = true
                    retryEnabled = false
                    retryTimerTask?.cancel()
                    retryTimerTask = nil
                    pathMonitor?.cancel()
                    pathMonitor = nil
                }

            case .failure:
                if !bootstrapCompleted {
                    bootstrapCompleted = true
                    bootstrapTimerTask?.cancel()
                    bootstrapTimerTask = nil
                    if current == nil {
                        _ = applyIfChanged(cacheStore.load() ?? .default)
                    }
                    if !stopConditionReached {
                        retryEnabled = true
                    }
                } else if retryEnabled && !stopConditionReached {
                    logger?.logD(source: self, prefix: "eventLoop", message: "Retry attempt failed via \(trigger.rawValue)")
                }
            }
        }

        if retryEnabled && !stopConditionReached && !inFlightAttempt && retryTimerTask == nil {
            let lastIndex = retryScheduleSeconds.count - 1
            let scheduleIndex = min(retryDelayIndex, lastIndex)
            let delaySeconds = retryScheduleSeconds[scheduleIndex]
            if retryDelayIndex < lastIndex {
                retryDelayIndex += 1
            }

            retryTimerTask = taskScope.spawn { [weak self] in
                do {
                    try await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
                } catch {
                    return
                }
                if Task.isCancelled { return }
                await self?.reduce(.retryTick)
            }
        }
    }

    private func launchAttemptIfPossible(trigger: Trigger) {
        guard !stopConditionReached else { return }
        guard !inFlightAttempt else { return }
        guard trigger == .startup || retryEnabled else { return }

        inFlightAttempt = true
        _ = taskScope.spawn { [weak self] in
            guard let self else { return }

            let outcome = await self.api.start(params: AppConfigAPIParams()).fold(
                onSuccess: { config in
                    self.logger?.logD(source: self, prefix: "performAttempt", message: "Server log level is: \(config.logLevel.rawValue)")
                    return AttemptOutcome.success(config)
                },
                onError: { error in
                    self.logger?.logW(
                        source: self,
                        prefix: "performAttempt",
                        message: "AppConfig attempt failed [\(trigger.rawValue)]: \(error.message)"
                    )
                    return AttemptOutcome.failure
                },
                onCanceled: {
                    self.logger?.logD(
                        source: self,
                        prefix: "performAttempt",
                        message: "AppConfig attempt canceled [\(trigger.rawValue)]"
                    )
                    return AttemptOutcome.failure
                }
            )

            await self.reduce(.attemptCompleted(trigger: trigger, outcome: outcome))
        }
    }

    private func applyIfChanged(_ config: AppConfig) -> Bool {
        if let current, current == config {
            return false
        }

        current = config
        updateLoginIdConfiguration(config)

        for continuation in continuations.values {
            continuation.yield(config)
        }

        let pending = waiters
        waiters.removeAll()
        for continuation in pending.values {
            continuation.resume(returning: config)
        }

        return true
    }

    private func updateLoginIdConfiguration(_ config: AppConfig) {
        guard let provider = loginIdConfigurationProvider else { return }

        var seen = Set<LoginIDType>()
        var supportedTypes: [LoginIDType] = []
        var regexes: [LoginIDType: NSRegularExpression?] = [:]

        for item in config.loginIdConfig where seen.insert(item.type).inserted {
            supportedTypes.append(item.type)

            let compiledRegex: NSRegularExpression?
            if let pattern = item.regex {
                do {
                    compiledRegex = try NSRegularExpression(pattern: pattern)
                } catch {
                    logger?.logW(
                        source: self,
                        prefix: "setConfiguration",
                        message: "Failed to parse regex for \(item.type): \(error.localizedDescription)",
                        cause: error
                    )
                    compiledRegex = nil
                }
            } else {
                compiledRegex = nil
            }

            regexes[item.type] = compiledRegex
        }

        provider.setServerConfiguration(LoginIDConfiguration(supportedTypes: supportedTypes, validationRegexes: regexes))
    }

    internal func isNetworkMonitoringActiveForTest() -> Bool {
        pathMonitor != nil
    }
}

private struct CacheStore {
    private let fileManager: FileManager
    private let fileURL: URL
    private let isWritable: Bool
    private let coder: any JSONCoder
    private let logger: OwnIDLogRouter?

    init(
        configuration: any OwnIDConfiguration,
        coder: any JSONCoder,
        fileManager: FileManager = .default,
        logger: OwnIDLogRouter?
    ) {
        self.fileManager = fileManager
        self.coder = coder
        self.logger = logger

        let suffix = "\(configuration.env().rawValue.lowercased())_\(configuration.region.rawValue.lowercased())_\(configuration.appID)"
        let appSupportBase = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        var directoryURL = (appSupportBase ?? fileManager.temporaryDirectory)
            .appendingPathComponent("com.ownid.sdk/config", isDirectory: true)
        var writable = true

        if appSupportBase == nil {
            logger?.logW(
                source: Self.self,
                prefix: #function,
                message: "Application Support directory not found; falling back to temporaryDirectory"
            )
        }

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
            Self.excludeFromBackup(directoryURL, logger: logger)
        } catch {
            logger?.logW(
                source: Self.self,
                prefix: #function,
                message: "Failed to create app config directory at \(directoryURL.path)",
                cause: error
            )

            directoryURL = fileManager.temporaryDirectory.appendingPathComponent("com.ownid.sdk/config", isDirectory: true)
            do {
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
                Self.excludeFromBackup(directoryURL, logger: logger)
            } catch {
                writable = false
                logger?.logW(
                    source: Self.self,
                    prefix: #function,
                    message: "App config persistence disabled: directory is unavailable"
                )
            }
        }

        self.fileURL = directoryURL.appendingPathComponent("appconfig_\(suffix).json")
        self.isWritable = writable
    }

    func load() -> AppConfig? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: fileURL)
            let contentString = String(data: data, encoding: .utf8) ?? ""
            return try coder.decodeFromString(contentString, as: AppConfig.self)
        } catch {
            logger?.logW(
                source: Self.self,
                prefix: #function,
                message: "Failed to read stored app config. Deleting corrupted file.",
                cause: error
            )
            try? fileManager.removeItem(at: fileURL)
            return nil
        }
    }

    func save(_ config: AppConfig) {
        guard isWritable else {
            logger?.logI(source: Self.self, prefix: #function, message: "App config directory is not writable; skipping write")
            return
        }

        do {
            let payload = try coder.encodeToString(config)
            guard let data = payload.data(using: .utf8) else { return }
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            try data.write(to: fileURL, options: .atomic)
            Self.excludeFromBackup(fileURL, logger: logger)
        } catch {
            logger?.logW(source: Self.self, prefix: #function, message: "Failed to persist app config", cause: error)
        }
    }

    private static func excludeFromBackup(_ url: URL, logger: OwnIDLogRouter?) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        do {
            try mutableURL.setResourceValues(values)
        } catch {
            logger?.logW(source: Self.self, prefix: #function, message: "Failed to mark path as excluded from backup: \(url.path)")
        }
    }
}
