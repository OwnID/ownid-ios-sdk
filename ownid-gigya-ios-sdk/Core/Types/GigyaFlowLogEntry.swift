import Foundation
import OwnIDCoreSDK

extension OwnID.GigyaSDK {
    public class FlowLogEntry: OwnID.CoreSDK.StandardMetricLogEntry {
        internal init(context: String,
                      requestPath: String? = .none,
                      logLevel: OwnID.CoreSDK.LogLevel = .information,
                      message: String,
                      codeInitiator: String) {
            super.init(context: context,
                       requestPath: requestPath,
                       level: logLevel,
                       message: message,
                       codeInitiator: codeInitiator,
                       sdkName: OwnID.GigyaSDK.sdkName,
                       version: OwnID.GigyaSDK.version)
        }
    }
}

public extension OwnID.GigyaSDK.FlowLogEntry {
    static func entry<T>(function: String = #function, file: String = #file, context: String = "no_context", message: String = "", _ : T.Type = T.self) -> OwnID.GigyaSDK.FlowLogEntry {
        OwnID.GigyaSDK.FlowLogEntry(context: context, message: "\(message) \(function) \(file)", codeInitiator: String(describing: T.self))
    }
    
    static func errorEntry<T>(function: String = #function, file: String = #file, context: String = "no_context", message: String = "", _ : T.Type = T.self) -> OwnID.GigyaSDK.FlowLogEntry {
        OwnID.GigyaSDK.FlowLogEntry(context: context, logLevel: .error, message: "\(message) \(function) \(file)", codeInitiator: String(describing: T.self))
    }
}

extension LoggerProtocol {
    func logGigya(_ entry: OwnID.GigyaSDK.FlowLogEntry) {
        self.log(entry)
    }
}

