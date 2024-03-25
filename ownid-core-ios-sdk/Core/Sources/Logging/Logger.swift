import Foundation

public protocol LoggerProtocol {
    func add(_ logger: ExtensionLoggerProtocol)
    func remove(_ logger: ExtensionLoggerProtocol)
    func log(_ entry: OwnID.CoreSDK.StandardMetricLogEntry, isMetric: Bool)
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

public protocol ExtensionLoggerProtocol {
    var identifier: UUID { get }
    
    func log(_ entry: OwnID.CoreSDK.StandardMetricLogEntry)
}

extension OwnID.CoreSDK {
    final class Logger: LoggerProtocol {
        static let shared = Logger()
        private init() { }
        private var sessionRequestSequenceNumber = 0
        var logLevel: LogLevel = .warning
        private var sdkNotConfiguredLogs = [StandardMetricLogEntry]()
        private var isSDKConfigured = false
        
        private var extendedLoggers = [ExtensionLoggerProtocol]()
        
        func sdkConfigured() {
            isSDKConfigured = true
            sdkNotConfiguredLogs.forEach { sendLog($0) }
            sdkNotConfiguredLogs.removeAll()
        }
        
        func add(_ logger: ExtensionLoggerProtocol) {
            extendedLoggers.append(logger)
        }
        
        func remove(_ logger: ExtensionLoggerProtocol) {
            if let index = extendedLoggers.firstIndex(where: { $0.identifier == logger.identifier }) {
                extendedLoggers.remove(at: index)
            }
        }
        
        func log(_ entry: StandardMetricLogEntry, isMetric: Bool) {
            if isMetric {
                sendMetric(entry)
            } else {
                if !isSDKConfigured {
                    sdkNotConfiguredLogs.append(entry)
                } else {
                    sendLog(entry)
                }
            }
        }
        
        private func sendMetric(_ entry: StandardMetricLogEntry) {
            entry.metadata[LoggerValues.correlationIDKey] = LoggerValues.instanceID.uuidString
            entry.metadata["sessionRequestSequenceNumber"] = String(sessionRequestSequenceNumber)
            entry.version = UserAgentManager.shared.userFacingSDKVersion
            entry.userAgent = UserAgentManager.shared.SDKUserAgent
            sessionRequestSequenceNumber += 1
            extendedLoggers.forEach { logger in
                logger.log(entry)
            }
        }
        
        private func sendLog(_ entry: StandardMetricLogEntry) {
            guard let level = entry.level, logLevel.rawValue <= level.rawValue else {
                return
            }
            
            entry.metadata[LoggerValues.correlationIDKey] = LoggerValues.instanceID.uuidString
            entry.metadata["sessionRequestSequenceNumber"] = String(sessionRequestSequenceNumber)
            entry.version = UserAgentManager.shared.userFacingSDKVersion
            entry.userAgent = UserAgentManager.shared.SDKUserAgent
            sessionRequestSequenceNumber += 1
            extendedLoggers.forEach { logger in
                logger.log(entry)
            }
        }
    }
}
