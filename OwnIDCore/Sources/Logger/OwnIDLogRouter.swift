import Foundation

/// Internal fan-out point for local SDK logs and instance-scoped server diagnostics.
///
/// Local logging and server diagnostics are independent sinks. Each log call is offered to the currently configured
/// ``OwnIDLogger`` and to every active ``ServerLogger``. The local logger applies the app-configured threshold; each
/// server logger applies the instance diagnostics threshold from remote ``AppConfig`` before sending.
///
/// A missing message is normalized to an empty string. Callers may pass an optional ``Error`` when the diagnostic is tied
/// to a failure. Logging must remain a best-effort side effect: callers do not observe delivery success, server
/// acceptance, or local sink failures through this API.
@_spi(OwnIDInternal) public final class OwnIDLogRouter: Sendable {
    private let ownIDLoggerProvider: @Sendable () -> (any OwnIDLogger)?
    private let serverLoggersProvider: @Sendable () -> [ServerLogger]

    internal init(
        ownIDLoggerProvider: @escaping @Sendable () -> (any OwnIDLogger)?,
        serverLoggersProvider: @escaping @Sendable () -> [ServerLogger]
    ) {
        self.ownIDLoggerProvider = ownIDLoggerProvider
        self.serverLoggersProvider = serverLoggersProvider
    }

    /// Logs a verbose message to local and server loggers.
    public func logV(source: Any, prefix: String, message: String?, cause: (any Error)? = nil) {
        log(level: .verbose, source: source, prefix: prefix, message: message, cause: cause)
    }

    /// Logs a debug message to local and server loggers.
    public func logD(source: Any, prefix: String, message: String?, cause: (any Error)? = nil) {
        log(level: .debug, source: source, prefix: prefix, message: message, cause: cause)
    }

    /// Logs an info message to local and server loggers.
    public func logI(source: Any, prefix: String, message: String?, cause: (any Error)? = nil) {
        log(level: .info, source: source, prefix: prefix, message: message, cause: cause)
    }

    /// Logs a warning message to local and server loggers.
    public func logW(source: Any, prefix: String, message: String?, cause: (any Error)? = nil) {
        log(level: .warn, source: source, prefix: prefix, message: message, cause: cause)
    }

    /// Logs an error message to local and server loggers.
    public func logE(source: Any, prefix: String, message: String?, cause: (any Error)? = nil) {
        log(level: .error, source: source, prefix: prefix, message: message, cause: cause)
    }

    private func log(level: LogLevel, source: Any, prefix: String, message: String?, cause: (any Error)?) {
        let type: Any.Type = (source as? Any.Type) ?? Swift.type(of: source)
        var typeName = String(describing: type)
        if let idx = typeName.firstIndex(of: "<") { typeName = String(typeName[..<idx]) }
        let hash: Int = (source as AnyObject?).map { ObjectIdentifier($0).hashValue } ?? abs(typeName.hashValue)
        let thread = Thread.isMainThread ? "main" : (Thread.current.name?.isEmpty == false ? Thread.current.name! : "background")
        let classNameLocal = "\(typeName)#\(hash)@\(thread):\(prefix)"

        ownIDLoggerProvider()?.log(level: level, className: classNameLocal, message: message ?? "", cause: cause)

        let serverLoggers = serverLoggersProvider()
        for serverLogger in serverLoggers {
            serverLogger.log(level: level, className: "\(typeName):\(prefix)", message: message ?? "", cause: cause)
        }
    }
}
