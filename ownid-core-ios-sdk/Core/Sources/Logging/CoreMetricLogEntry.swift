import Foundation

extension OwnID.CoreSDK {
    public final class CoreMetricLogEntry: StandardMetricLogEntry {
        internal init(context: String?,
                      requestPath: String? = .none,
                      logLevel: LogLevel = .information,
                      message: String,
                      codeInitiator: String) {
            super.init(context: context,
                       requestPath: requestPath,
                       level: logLevel,
                       message: message,
                       codeInitiator: codeInitiator,
                       sdkName: OwnID.CoreSDK.sdkName,
                       version: OwnID.CoreSDK.version)
        }
    }
}

public extension OwnID.CoreSDK.CoreMetricLogEntry {
    static func entry<T>(level: OwnID.CoreSDK.LogLevel = .information, function: String = #function, file: String = #file, context: String? = nil, message: String = "", _ : T.Type = T.self) -> OwnID.CoreSDK.CoreMetricLogEntry {
        OwnID.CoreSDK.CoreMetricLogEntry(context: context,
                                         logLevel: level,
                                         message: "\(message) \(function) \((file as NSString).lastPathComponent)",
                                         codeInitiator: String(describing: T.self))
    }
    
    static func errorEntry<T>(function: String = #function, file: String = #file, context: String? = nil, message: String = "", _ : T.Type = T.self) -> OwnID.CoreSDK.CoreMetricLogEntry {
        OwnID.CoreSDK.CoreMetricLogEntry(context: context,
                                         logLevel: .error,
                                         message: "\(message) \(function) \((file as NSString).lastPathComponent)",
                                         codeInitiator: String(describing: T.self))
    }
}

extension LoggerProtocol {
    func logCore(_ entry: OwnID.CoreSDK.CoreMetricLogEntry) {
        self.log(entry, isMetric: false)
    }
}
