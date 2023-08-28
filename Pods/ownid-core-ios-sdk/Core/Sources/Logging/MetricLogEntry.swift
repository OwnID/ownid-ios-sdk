import Foundation

public extension OwnID.CoreSDK.StandardMetricLogEntry {
    enum EventType: String, Encodable {
        case click
        case track
        case error
    }
    
    enum EventCategory: String, Encodable {
        case registration
        case login
    }
}

public extension OwnID.CoreSDK {
    final class MetricLogEntry: StandardMetricLogEntry {
        public init(action: String,
                    type: EventType,
                    category: EventCategory,
                    context: String,
                    metadata: [String : String?] = [String : String]()) {
            super.init(context: context, message: "", codeInitiator: "\(Self.self)", sdkName: OwnID.CoreSDK.sdkName, version: OwnID.CoreSDK.UserAgentManager.shared.userFacingSDKVersion,
                       metadata: metadata)
            self.type = type
            self.action = action
            self.category = category
        }
    }
}

public extension OwnID.CoreSDK.MetricLogEntry {
    private static func authTypeKey(authType: String?) -> [String: String?] {
        ["authType": authType]
    }
    
    static func registerTrackMetric(action: String,
                                    context: String? = "no_context",
                                    authType: String? = .none) -> OwnID.CoreSDK.MetricLogEntry {
        let metric = OwnID.CoreSDK.MetricLogEntry.init(action: action,
                                                       type: .track,
                                                       category: .registration,
                                                       context: context ?? "no_context",
                                                       metadata: authTypeKey(authType: authType))
        return metric
    }
    
    static func registerClickMetric(action: String, context: String? = "no_context") -> OwnID.CoreSDK.MetricLogEntry {
        let metric = OwnID.CoreSDK.MetricLogEntry.init(action: action, type: .click, category: .registration, context: context ?? "no_context")
        return metric
    }
    
    static func loginTrackMetric(action: String,
                                 context: String? = "no_context",
                                 authType: String? = .none) -> OwnID.CoreSDK.MetricLogEntry {
        let metric = OwnID.CoreSDK.MetricLogEntry.init(action: action,
                                                       type: .track,
                                                       category: .login,
                                                       context: context ?? "no_context",
                                                       metadata: authTypeKey(authType: authType))
        return metric
    }
    
    static func loginClickMetric(action: String, context: String? = "no_context") -> OwnID.CoreSDK.MetricLogEntry {
        let metric = OwnID.CoreSDK.MetricLogEntry.init(action: action, type: .click, category: .login, context: context ?? "no_context")
        return metric
    }
}

extension LoggerProtocol {
    public func logAnalytic(_ entry: OwnID.CoreSDK.MetricLogEntry) {
        self.log(entry)
    }
}
