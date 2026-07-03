import Foundation

/// Instance-scoped server log sink for diagnostics allowed by remote ``AppConfig``.
///
/// Local SDK logging and server logging are separate sinks. This logger accepts SDK diagnostics for one
/// ``InstanceName``, waits until remote AppConfig is available, filters events by the server-configured level, and posts
/// accepted events to OwnID diagnostics using the instance configuration. If diagnostics cannot be configured for the
/// instance, server diagnostics are disabled for that instance.
///
/// Delivery is best effort. Calls to ``log(level:className:message:cause:)`` never suspend or report success to the
/// caller. Diagnostics can be dropped when the instance is shutting down, remote logging is disabled, payload preparation
/// fails, or delivery cannot complete. Transport failures may be retried internally. Local logging may receive summaries
/// of diagnostics delivery failures, but those failures do not affect the SDK operation that emitted the diagnostic.
///
/// Server diagnostics may include the source label, message, exception text, SDK version, request client string, and device/app
/// metadata available from ``LocalInfo``. HTTP logging for diagnostics posts is suppressed so diagnostics do not
/// recursively log themselves.
internal final class ServerLogger: @unchecked Sendable {
    internal typealias RetryDelayProvider = @Sendable (_ attempt: Int) -> UInt64
    internal typealias RetrySleeper = @Sendable (_ delayNanos: UInt64) async throws -> Void

    private struct PostponedLog: Sendable {
        fileprivate let level: LogLevel
        fileprivate let codeInitiator: String
        fileprivate let message: String
        fileprivate let exception: String?
        fileprivate let resendCount: Int
    }

    private struct Metadata: Encodable, Sendable {
        fileprivate let correlationId: String
        fileprivate let bundleId: String
        fileprivate let isUserVerifyingPlatformAuthenticatorAvailable: Bool
        fileprivate let isDeviceSecured: Bool
        fileprivate let isFingerprintHardwarePresent: Bool
        fileprivate let isFaceHardwarePresent: Bool
        fileprivate let isStrongBiometricEnabled: Bool
    }

    private let instanceName: InstanceName
    private let localInfo: any LocalInfo
    private let appConfigProvider: any AppConfigProvider
    private let network: any NetworkProtocol
    private let coder: any JSONCoder
    private let taskScope: TaskScope
    private let ownIdLogger: (any OwnIDLogger)?
    private let retryDelayProvider: RetryDelayProvider
    private let retrySleeper: RetrySleeper

    private let eventsURL: URL?
    private let stream: AsyncStream<PostponedLog>
    private let continuation: AsyncStream<PostponedLog>.Continuation
    private let thresholdLock = NSLock()
    private var storedThreshold: LogLevel = AppConfig.default.logLevel.toLogLevel()
    private var consumerTask: Task<Void, Never>?
    private var thresholdObservationTask: Task<Void, Never>?
    private let metadata: Metadata

    private var currentThreshold: LogLevel {
        get { thresholdLock.withLock { storedThreshold } }
        set { thresholdLock.withLock { storedThreshold = newValue } }
    }

    internal init(
        instanceName: InstanceName,
        configuration: any OwnIDConfiguration,
        localInfo: any LocalInfo,
        appConfigProvider: any AppConfigProvider,
        network: any NetworkProtocol,
        coder: any JSONCoder,
        taskScope: TaskScope,
        ownIdLogger: (any OwnIDLogger)? = nil,
        retryDelayProvider: @escaping RetryDelayProvider = ServerLogger.defaultRetryDelayNanos(for:),
        retrySleeper: @escaping RetrySleeper = { try await Task.sleep(nanoseconds: $0) }
    ) {
        self.instanceName = instanceName
        self.localInfo = localInfo
        self.appConfigProvider = appConfigProvider
        self.network = network
        self.coder = coder
        self.taskScope = taskScope
        self.ownIdLogger = ownIdLogger
        self.retryDelayProvider = retryDelayProvider
        self.retrySleeper = retrySleeper

        self.metadata = Metadata(
            correlationId: localInfo.correlationId,
            bundleId: localInfo.bundleID,
            isUserVerifyingPlatformAuthenticatorAvailable: localInfo.isSystemFidoCapable,
            isDeviceSecured: localInfo.isDeviceSecured,
            isFingerprintHardwarePresent: localInfo.isFingerprintHardwarePresent,
            isFaceHardwarePresent: localInfo.isFaceHardwarePresent,
            isStrongBiometricEnabled: localInfo.isStrongBiometricEnabled
        )

        if let rootURL = configuration.rootURL, let baseURL = URL(string: rootURL) {
            self.eventsURL = baseURL.appendingPathComponent("events")
        } else {
            var components = URLComponents()
            components.scheme = "https"
            components.host =
                "\(configuration.appID).server\(configuration.toStringPrefix()).ownid\(configuration.region.toStringSuffix()).com"
            components.path = "/events"
            self.eventsURL = components.url
        }

        var cont: AsyncStream<PostponedLog>.Continuation!
        self.stream = AsyncStream<PostponedLog>(bufferingPolicy: .bufferingOldest(1000)) { continuation in
            cont = continuation
        }
        self.continuation = cont

        if self.eventsURL == nil {
            ownIdLogger?.log(
                level: .warn,
                className: "ServerLogger",
                message:
                    "Invalid events URL (appID: \(configuration.appID), env: \(configuration.env().rawValue), region: \(configuration.region)). Server logs disabled.",
                cause: nil
            )
            continuation.finish()
        } else {
            startConsumer()
        }
    }

    deinit {
        continuation.finish()
        thresholdObservationTask?.cancel()
        consumerTask?.cancel()
    }

    /// Records a best-effort server diagnostic unless `level` is ``LogLevel/off``.
    internal func log(level: LogLevel, className: String, message: String, cause: (any Error)?) {
        guard level != .off else { return }
        guard eventsURL != nil else { return }

        let item = PostponedLog(
            level: level,
            codeInitiator: "[\(instanceName.description)]\(className)",
            message: "\(className) => \(message)",
            exception: cause?.localizedDescription,
            resendCount: 0
        )

        continuation.yield(item)
    }

    private func startConsumer() {
        thresholdObservationTask = taskScope.spawn { [weak self] in
            guard let self else { return }
            for await config in self.appConfigProvider.configStream {
                self.currentThreshold = config.logLevel.toLogLevel()
            }
        }

        consumerTask = taskScope.spawn { [weak self] in
            guard let self else { return }
            do {
                self.currentThreshold = (try await self.appConfigProvider.getOrFetchConfig()).logLevel.toLogLevel()
            } catch is CancellationError {
                return
            } catch {
                return
            }
            for await log in self.stream {
                if !self.currentThreshold.isEnabled(log.level) { continue }
                await self.send(log)
            }
        }
        if consumerTask == nil {
            continuation.finish()
        }
    }

    internal static func defaultRetryDelayNanos(for attempt: Int) -> UInt64 {
        let baseMs: UInt64 = 500
        let maxMs: UInt64 = 2_000
        let factor = UInt64(1) << UInt64(max(0, attempt - 1))
        let delayMs = min(maxMs, baseMs &* factor)
        let jitterMs = UInt64.random(in: 0..<(delayMs / 4 + 1))
        return (delayMs + jitterMs) * 1_000_000
    }

    private func scheduleRetry(for log: PostponedLog) {
        let nextCount = log.resendCount + 1
        let delay = retryDelayProvider(nextCount)

        _ = taskScope.spawn { [weak self] in
            guard let self else { return }
            do {
                try await self.retrySleeper(delay)
            } catch is CancellationError {
                return
            } catch {
                return
            }
            if Task.isCancelled { return }
            self.continuation.yield(
                PostponedLog(
                    level: log.level,
                    codeInitiator: log.codeInitiator,
                    message: log.message,
                    exception: log.exception,
                    resendCount: nextCount
                )
            )
            self.ownIdLogger?.log(
                level: .debug,
                className: "ServerLogger",
                message: "Retry scheduled after \(delay / 1_000_000)ms (attempt \(nextCount))",
                cause: nil
            )
        }
    }

    private func send(_ log: PostponedLog) async {

        struct LogItem: Encodable {
            let component: String
            let level: AppConfig.LogLevel
            let codeInitiator: String
            let message: String
            let exception: String?
            let metadata: Metadata
            let userAgent: String
            let version: String
            let sourceTimestamp: String
        }

        let serverLevel: AppConfig.LogLevel = {
            switch log.level {
            case .verbose, .debug: return .debug
            case .info: return .information
            case .warn: return .warning
            case .error, .assert: return .error
            case .off: return .none
            }
        }()

        let payload = LogItem(
            component: "IosSdk",
            level: serverLevel,
            codeInitiator: log.codeInitiator,
            message: log.message,
            exception: log.exception,
            metadata: self.metadata,
            userAgent: localInfo.userAgent,
            version: localInfo.appVersion,
            sourceTimestamp: String(Int64(Date().timeIntervalSince1970 * 1000))
        )

        guard let eventsURL else { return }

        let body: String
        do { body = try coder.encodeToString(payload) } catch {
            ownIdLogger?.log(level: .warn, className: "ServerLogger", message: "Failed to serialize log item", cause: error)
            return
        }

        var request = NetworkRequest(url: eventsURL)
        request.setSuppressHttpLog()
        request.setBody(body)

        do {
            let response = try await network.run(request)
            switch response {
            case .success:
                return
            case .fail(let fail):
                ownIdLogger?.log(level: .info, className: "ServerLogger", message: String(describing: fail), cause: nil)
                if case .networkError = fail, log.resendCount < 2 {
                    scheduleRetry(for: log)
                }
            }
        } catch is CancellationError {
            return
        } catch {
            ownIdLogger?.log(level: .info, className: "ServerLogger", message: String(describing: error), cause: error)
        }
    }
}

extension AppConfig.LogLevel {
    fileprivate func toLogLevel() -> LogLevel {
        switch self {
        case .debug: return .debug
        case .information: return .info
        case .warning: return .warn
        case .error: return .error
        case .none: return .off
        }
    }
}
