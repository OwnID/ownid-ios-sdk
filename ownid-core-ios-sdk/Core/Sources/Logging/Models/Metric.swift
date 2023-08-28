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
        case fidoRun(category: EventCategory)
        case fidoNotFinished(category: EventCategory)
        case fidoFinished(category: EventCategory)
        case loginId
        case wrongOTP
        case correctOTP
        case noOTP
        case notYou
        case screenShow(screen: String)
        case fidoSupports(isFidoSupported: Bool)
        case userPastedCode
        case error
                
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
                return "Clicked Skip Password Undo"
            case .cancel:
                return "Screen canceled by user"
            case .fidoRun(let category):
                return "FIDO \(category): About To Execute"
            case .fidoNotFinished(let category):
                return "FIDO \(category): Execution Did Not Complete"
            case .fidoFinished(let category):
                return "FIDO \(category): Execution Completed Successfully"
            case .loginId:
                return "User entered login id"
            case .wrongOTP:
                return "User entered wrong OTP"
            case .correctOTP:
                return "Entered Correct Verification Code"
            case .noOTP:
                return "User select: No OTP"
            case .notYou:
                return "Clicked Not You"
            case .screenShow(let screen):
                return "Screen show: \(screen)"
            case .fidoSupports(let isFidoSupported):
                return "System supports FIDO: \(isFidoSupported)"
            case .userPastedCode:
                return "User Pasted Verification Code"
            case .error:
                return "Error"
            }
        }
        
        var isPositionAndTypeAdding: Bool {
            switch self {
            case .loggedIn,
                    .registered,
                    .undo,
                    .cancel,
                    .fidoRun,
                    .fidoNotFinished,
                    .fidoFinished,
                    .loginId,
                    .wrongOTP,
                    .correctOTP,
                    .noOTP,
                    .notYou,
                    .screenShow,
                    .fidoSupports,
                    .userPastedCode,
                    .error:
                return false
            case .loaded, .click:
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
        public var userAgent = UserAgentManager.shared.SDKUserAgent
        public var version = UserAgentManager.shared.userFacingSDKVersion
        public var sourceTimestamp = String(Int((Date().timeIntervalSince1970 * 1000.0).rounded()))
        
        init(context: String? = LoggerConstants.noContext,
             category: EventCategory,
             type: EventType,
             action: String?,
             metadata: Metadata? = nil,
             loginId: String? = nil,
             errorMessage: String? = nil) {
            self.context = context ?? LoggerConstants.noContext
            self.category = category
            self.type = type
            self.action = action
            self.metadata = metadata
            self.loginId = loginId
            self.errorMessage = errorMessage
        }
        
        private static func metricloginId(_ loginId: String?) -> String? {
            if let loginId {
                return SHA256.hash(data: Data((loginId).utf8)).data.toBase64URL()
            }
            return nil
        }
        
        public static func trackMetric(action: AnalyticActionType,
                                       category: EventCategory,
                                       context: String? = LoggerConstants.noContext,
                                       loginId: String? = nil,
                                       authType: String? = nil) -> Metric {
            Metric(context: context ?? LoggerConstants.noContext,
                   category: category,
                   type: .track,
                   action: action.actionValue,
                   metadata: Metadata.metadata(authType: authType, actionType: action),
                   loginId: metricloginId(loginId))
        }
        
        public static func clickMetric(action: AnalyticActionType,
                                       category: EventCategory,
                                       context: String? = LoggerConstants.noContext,
                                       loginId: String? = nil,
                                       hasLoginId: Bool? = nil) -> Metric {
            Metric(context: context ?? LoggerConstants.noContext,
                   category: category,
                   type: .click,
                   action: action.actionValue,
                   metadata: Metadata.metadata(actionType: action, hasLoginId: hasLoginId),
                   loginId: metricloginId(loginId))
        }
        
        public static func errorMetric(action: AnalyticActionType,
                                       category: EventCategory,
                                       context: String? = LoggerConstants.noContext,
                                       loginId: String? = nil,
                                       errorMessage: String?) -> Metric {
            Metric(context: context ?? LoggerConstants.noContext,
                   category: category,
                   type: .error,
                   action: action.actionValue,
                   metadata: Metadata.metadata(actionType: action),
                   loginId: metricloginId(loginId),
                   errorMessage: errorMessage)
        }
    }
}
