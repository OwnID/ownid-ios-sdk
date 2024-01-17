import Foundation
import CryptoKit

public extension OwnID.CoreSDK {
    enum EventType: String, Encodable {
        case click
        case track
        case pageView
        case error
    }
    
    enum EventCategory: String, Encodable {
        case registration
        case login
    }
    
    enum AnalyticActionType {
        case loggedIn
        case registered
        case loaded
        case click
        case undo
        case cancel
        case fidoRun
        case fidoNotFinished
        case fidoFinished
        case fidoFailed
        case loginId
        case wrongOTP(name: String)
        case correctOTP(name: String)
        case resendOTP
        case notYou
        case screenShow(screen: String)
        case fidoSupports(isFidoSupported: Bool)
        case userPastedCode
        case error(message: String)
                
        var actionValue: String {
            switch self {
            case .loggedIn:
                return "User is Logged in"
            case .registered:
                return "User is Registered"
            case .loaded:
                return "OwnID Widget is Loaded"
            case .click:
                return "Clicked Skip Password"
            case .undo:
                return "Clicked Undo"
            case .cancel:
                return "Clicked Cancel"
            case .fidoRun:
                return "FIDO: About To Execute"
            case .fidoNotFinished:
                return "FIDO: Execution Did Not Complete"
            case .fidoFinished:
                return "FIDO: Execution Completed Successfully"
            case .fidoFailed:
                return "FIDO: Failed, trying to register new one"
            case .loginId:
                return "User entered Login ID"
            case .wrongOTP(let name):
                return "[\(name)] - Entered Wrong Verification Code"
            case .correctOTP(let name):
                return "[\(name)] - Entered Correct Verification Code"
            case .resendOTP:
                return "User select: Resend"
            case .notYou:
                return "Clicked Not You"
            case .screenShow(let screen):
                return "Viewed \(screen)"
            case .fidoSupports(let isFidoSupported):
                return "Passkey Supported: \(isFidoSupported)"
            case .userPastedCode:
                return "User Pasted Verification Code"
            case .error(let message):
                return "Sending error to app \(message)"
            }
        }
        
        var isPositionAndTypeAdding: Bool {
            switch self {
            case .loggedIn,
                    .registered,
                    .cancel,
                    .fidoRun,
                    .fidoNotFinished,
                    .fidoFinished,
                    .fidoFailed,
                    .loginId,
                    .wrongOTP,
                    .correctOTP,
                    .resendOTP,
                    .notYou,
                    .screenShow,
                    .fidoSupports,
                    .userPastedCode,
                    .error:
                return false
            case .loaded, .click, .undo:
                return true
            }
        }
    }
    
    struct CurrentMetricInformation {
        public init(widgetType: WidgetType = .client,
                    widgetPositionType: WidgetPositionType = .start) {
            self.widgetType = widgetType
            self.widgetPositionType = widgetPositionType
        }
        
        var widgetType = WidgetType.client
        var widgetPositionType = WidgetPositionType.start
    }
    
    struct Metric: LogMetricProtocol {
        public var context: String
        public var component = LoggerConstants.component
        let category: EventCategory
        let type: EventType
        let action: String?
        public var metadata: Metadata?
        let loginId: String?
        let errorMessage: String?
        let source: String?
        public var userAgent = UserAgentManager.shared.SDKUserAgent
        public var version = UserAgentManager.shared.userFacingSDKVersion
        public var sourceTimestamp = String(Int((Date().timeIntervalSince1970 * 1000.0).rounded()))
        
        init(context: String? = "",
             category: EventCategory,
             type: EventType,
             action: String?,
             metadata: Metadata? = nil,
             loginId: String? = nil,
             errorMessage: String? = nil,
             source: String? = nil) {
            self.context = context ?? ""
            self.category = category
            self.type = type
            self.action = action
            self.metadata = metadata
            self.loginId = loginId
            self.errorMessage = errorMessage
            self.source = source
        }
        
        private static func metricloginId(_ loginId: String?) -> String? {
            if let loginId {
                return SHA256.hash(data: Data((loginId).utf8)).data.toBase64URL()
            }
            return nil
        }
        
        public static func trackMetric(action: AnalyticActionType,
                                       category: EventCategory,
                                       context: String? = "",
                                       loginId: String? = nil,
                                       authType: String? = nil,
                                       source: String? = nil) -> Metric {
            Metric(context: context ?? "",
                   category: category,
                   type: .track,
                   action: action.actionValue,
                   metadata: Metadata.metadata(authType: authType, actionType: action),
                   loginId: metricloginId(loginId),
                   source: source)
        }
        
        public static func clickMetric(action: AnalyticActionType,
                                       category: EventCategory,
                                       context: String? = "",
                                       loginId: String? = nil,
                                       hasLoginId: Bool? = nil,
                                       source: String? = nil) -> Metric {
            Metric(context: context ?? "",
                   category: category,
                   type: .click,
                   action: action.actionValue,
                   metadata: Metadata.metadata(actionType: action, hasLoginId: hasLoginId),
                   loginId: metricloginId(loginId),
                   source: source)
        }
        
        public static func errorMetric(action: AnalyticActionType,
                                       category: EventCategory,
                                       context: String? = "",
                                       loginId: String? = nil,
                                       errorMessage: String?,
                                       source: String? = nil) -> Metric {
            Metric(context: context ?? "",
                   category: category,
                   type: .error,
                   action: action.actionValue,
                   metadata: Metadata.metadata(actionType: action),
                   loginId: metricloginId(loginId),
                   errorMessage: errorMessage,
                   source: source)
        }
    }
}
