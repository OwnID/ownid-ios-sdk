import Foundation

public protocol LoggerProtocol {
    func log(priority: Int, codeInitiator: String, message: String, errorMessage: String?)
}

public extension OwnID.CoreSDK {
    class Logger {
        public var isEnabled = false
        
        private var tag: String = "OwnID-SDK"
        private var logger: LoggerProtocol = OSLogger()
        
        func setLogger(_ logger: LoggerProtocol = OSLogger(), customTag: String) {
            self.logger = logger
            tag = customTag
        }
        
        public func log(priority: Int, codeInitiator: String, message: String, errorMessage: String?) {
            if isEnabled {
                logger.log(priority: priority, codeInitiator: codeInitiator, message: message, errorMessage: errorMessage)
            }
        }
    }
}


public extension OwnID.CoreSDK {
    final class InternalLogger {
        static let shared = InternalLogger()
        private init() { }
        
        public var isEnabled = false {
            didSet {
                logger.updateIsEnabled(isEnabled: isEnabled)
            }
        }
        let logger = PrivateLogger()
        
        var context: String? {
            OwnID.CoreSDK.logger.logger.context
        }
        
        public func setLogger(_ logger: LoggerProtocol, customTag: String) {
            self.logger.setLogger(logger, customTag: customTag)
        }
        
        public func log(level: LogLevel,
                 function: String = #function,
                 file: String = #file,
                 message: String = "",
                 errorMessage: String? = nil,
                 force: Bool = false,
                 type: Any.Type = Any.self) {
            let message = "\(message) \(function) \((file as NSString).lastPathComponent)"
            if force {
                logger.forceLog(level: level, codeInitiator: String(describing: type.self), message: message, errorMessage: errorMessage)
            } else {
                logger.log(level: level, codeInitiator: String(describing: type.self), message: message, errorMessage: errorMessage)
            }
        }
        
        func updateContext(context: String?) {
            logger.context = context
        }
        
        func updateLogLevel(logLevel: LogLevel) {
            logger.logLevel = logLevel
        }
        
        func sdkConfigured() {
            logger.sdkConfigured()
        }
    }
}

extension OwnID.CoreSDK {
    final class PrivateLogger {
        init() { }
        
        var context: String?
        var logLevel = LogLevel.error
        
        private var logger = Logger()
        
        private var sessionRequestSequenceNumber: UInt = 0
        private var sdkNotConfiguredLogs = [LogItem]()

        func setLogger(_ logger: LoggerProtocol, customTag: String) {
            self.logger.setLogger(logger, customTag: customTag)
        }
        
        func sdkConfigured() {
            sdkNotConfiguredLogs.forEach { sendToLoggers($0) }
            sdkNotConfiguredLogs.removeAll()
        }
        
        func log(level: LogLevel, codeInitiator: String, message: String, errorMessage: String?) {
            var entry = LogItem(context: context ?? "",
                                level: level,
                                codeInitiator: codeInitiator,
                                message: message,
                                errorMessage: errorMessage)
            entry = setupLog(entry)
            
            if !OwnID.CoreSDK.shared.isSDKConfigured {
                sdkNotConfiguredLogs.append(entry)
            } else {
                sendToLoggers(entry)
            }
        }
        
        func forceLog(level: LogLevel, codeInitiator: String, message: String, errorMessage: String?) {
            var entry = LogItem(context: context ?? "",
                                level: level,
                                codeInitiator: codeInitiator,
                                message: message,
                                errorMessage: errorMessage)
            entry = setupLog(entry)
            
            sendToLoggers(entry)
        }
        
        func updateIsEnabled(isEnabled: Bool) {
            logger.isEnabled = isEnabled
        }
        
        private func setupLog(_ entry: LogItem) -> LogItem {
            let entry = entry
            entry.metadata = Metadata(correlationId: LoggerConstants.instanceID.uuidString,
                                      stackTrace: nil,
                                      sessionRequestSequenceNumber: String(sessionRequestSequenceNumber),
                                      widgetPosition: nil,
                                      widgetType: nil,
                                      authType: nil,
                                      hasLoginId: nil)
            
            sessionRequestSequenceNumber += 1
            
            return entry
        }

        private func sendToLoggers(_ entry: LogItem) {
            logger.log(priority: entry.level.priority,
                       codeInitiator: entry.codeInitiator ?? "",
                       message: entry.message,
                       errorMessage: entry.errorMessage)
            
            if entry.level.shouldLog(for: logLevel.priority) {
                OwnID.CoreSDK.eventService.log(entry)
            }
        }
    }
}

public extension String {
    var logValue: String {
        if isEmpty {
            return self
        }
        var prefixCount = count - 3
        if prefixCount <= 3 {
            prefixCount = 2
        }
        return String(self.prefix(prefixCount))
    }
}
