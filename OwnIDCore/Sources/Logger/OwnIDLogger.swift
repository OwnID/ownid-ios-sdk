import os

/// Severity threshold used by OwnID logging.
///
/// Higher values represent more severe messages. Use ``LogLevel/off`` to disable logging.
public enum LogLevel: Int, Sendable {
    case verbose = 2
    case debug = 3
    case info = 4
    case warn = 5
    case error = 6
    case assert = 7
    case off = 2_147_483_647

    /// Returns `true` when messages at `other` should be emitted under this threshold.
    @inlinable public func isEnabled(_ other: LogLevel) -> Bool {
        self != .off && other != .off && other.rawValue >= self.rawValue
    }
}

extension LogLevel {
    fileprivate var osLogType: OSLogType {
        switch self {
        case .verbose: return .debug
        case .debug: return .debug
        case .info: return .info
        case .warn: return .default
        case .error: return .error
        case .assert: return .fault
        default: return .default
        }
    }
}

/// Local logging abstraction used by the OwnID SDK.
///
/// Configure it with ``OwnID/logger(block:)``. The most recent logger replaces the previous SDK-wide logger and is used
/// for local SDK log events. Instance-scoped server diagnostics are a separate sink and are filtered by remote
/// ``AppConfig``.
///
/// If you never configure a logger, local SDK logging is silent. The SDK uses ``OwnIDDefaultLogger`` only as a temporary
/// fallback for early configuration failures before a configured SDK instance can provide local logging.
public protocol OwnIDLogger: Sendable {
    /// Logging threshold; messages below this level are ignored.
    var level: LogLevel { get }

    /// Category used for log messages.
    var category: String { get }

    /// Logs a message if the logger is enabled for the specified level.
    ///
    /// - Parameters:
    ///   - level: Severity of the log message.
    ///   - className: Name of the class that produced the log.
    ///   - message: Message to log.
    ///   - cause: Optional error associated with the log event.
    func log(level: LogLevel, className: String, message: String, cause: (any Error)?)
}

extension OwnIDLogger {
    @inlinable public func isEnabled(_ level: LogLevel) -> Bool { self.level.isEnabled(level) }
}

/// Default fallback logger backed by OSLog.
///
/// The SDK uses this logger only for early configuration failures before a configured SDK instance can provide local
/// logging. It is not installed globally unless you register it yourself.
public final class OwnIDDefaultLogger: OwnIDLogger {
    /// Creates a default logger with the given level and category.
    ///
    /// - Parameters:
    ///   - level: Logging threshold; defaults to ``LogLevel/warn``.
    ///   - category: Log category; defaults to `OwnID-SDK`.
    public static func make(level: LogLevel = .warn, category: String = "OwnID-SDK") -> OwnIDDefaultLogger {
        OwnIDDefaultLogger(category: category, level: level)
    }

    public let level: LogLevel
    public let category: String
    private let backend: LogBackend

    private init(category: String = "OwnID-SDK", level: LogLevel = .warn) {
        self.level = level
        self.category = category
        self.backend = LogBackend(category: category)
    }

    public func log(level: LogLevel, className: String, message: String, cause: (any Error)?) {
        guard isEnabled(level) else { return }
        let formatted = formatLogMessage(className: className, message: message, cause: cause)
        backend.log(level.osLogType, formatted)
    }
}

/// Builder for configuring an SDK-wide local logger.
///
/// Defaults: ``level`` is ``LogLevel/off`` and ``category`` is `OwnID-SDK`, so the built logger emits no local messages
/// until you lower the threshold. Without a custom log handler, enabled messages are written through OSLog with
/// subsystem `com.ownid.ios-sdk`. With a custom handler, enabled messages are forwarded to your handler; if the handler
/// throws, the failure is caught, reported through OSLog, and not rethrown.
///
/// Configure logging before SDK initialization when you need initialization logs or local HTTP logs. HTTP logs are local
/// only and are enabled when the logger accepts ``LogLevel/debug`` messages.
public class OwnIDLoggerBuilder {
    /// Logging threshold; messages below this level are ignored.
    public var level: LogLevel = .off

    /// Category used for log messages.
    public var category: String = "OwnID-SDK"

    private var customLogAction: (@Sendable (LogLevel, String, String, (any Error)?) throws -> Void)?

    /// Sets a custom sink for log events that can throw.
    ///
    /// The sink is invoked only for messages accepted by ``level``. Thrown errors are caught and reported through OSLog.
    ///
    /// - Parameter block: Callback invoked for each log event: (level, className, message, cause).
    public func log(_ block: @escaping @Sendable (LogLevel, String, String, (any Error)?) throws -> Void) {
        customLogAction = block
    }

    /// Sets a custom sink for log events.
    ///
    /// The sink is invoked only for messages accepted by ``level``.
    ///
    /// - Parameter block: Callback invoked for each log event: (level, className, message, cause).
    public func log(_ block: @escaping @Sendable (LogLevel, String, String, (any Error)?) -> Void) {
        customLogAction = { level, className, message, cause in
            block(level, className, message, cause)
        }
    }

    internal func apply(_ block: (OwnIDLoggerBuilder) -> Void) -> OwnIDLoggerBuilder {
        block(self)
        return self
    }

    internal func build() -> any OwnIDLogger {
        return BuiltLogger(
            level: level,
            category: category,
            backend: LogBackend(category: category),
            customLogAction: customLogAction
        )
    }

    private struct BuiltLogger: OwnIDLogger {
        fileprivate let level: LogLevel
        fileprivate let category: String
        fileprivate let backend: LogBackend
        fileprivate let customLogAction: (@Sendable (LogLevel, String, String, (any Error)?) throws -> Void)?

        fileprivate init(
            level: LogLevel,
            category: String,
            backend: LogBackend,
            customLogAction: (@Sendable (LogLevel, String, String, (any Error)?) throws -> Void)?
        ) {
            self.level = level
            self.category = category
            self.backend = backend
            self.customLogAction = customLogAction
        }

        fileprivate func log(level: LogLevel, className: String, message: String, cause: (any Error)?) {
            guard isEnabled(level) else { return }

            if let customLogAction {
                do {
                    try customLogAction(level, className, message, cause)
                } catch {
                    backend.error("Logging failed: \(String(describing: error))")
                }
            } else {
                let formatted = formatLogMessage(className: className, message: message, cause: cause)
                backend.log(level.osLogType, formatted)
            }
        }
    }
}

private struct LogBackend: Sendable {
    fileprivate let log: @Sendable (OSLogType, String) -> Void
    fileprivate let error: @Sendable (String) -> Void

    fileprivate init(category: String) {
        if #available(iOS 14, *) {
            let logger = Logger(subsystem: "com.ownid.ios-sdk", category: category)
            self.log = { type, message in
                logger.log(level: type, "\(message, privacy: .sensitive)")
            }
            self.error = { message in
                logger.log(level: .error, "\(message, privacy: .sensitive)")
            }
        } else {
            let oslog = OSLog(subsystem: "com.ownid.ios-sdk", category: category)
            self.log = { type, message in
                os_log("%{public}@", log: oslog, type: type, message)
            }
            self.error = { message in
                os_log("%{public}@", log: oslog, type: .error, message)
            }
        }
    }
}

private func formatLogMessage(className: String, message: String, cause: (any Error)?) -> String {
    if let cause { return "\(className) |> \(message)\n\(String(describing: cause))" }
    return "\(className) |> \(message)"
}
