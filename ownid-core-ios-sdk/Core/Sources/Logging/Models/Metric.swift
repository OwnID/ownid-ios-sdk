import Foundation
import CryptoKit

public extension OwnID.CoreSDK {
    enum EventType: String, Encodable {
        case click
        case track
        case pageView
        case error
    }
    
    enum EventCategory: String, Codable {
        case registration
        case login
        case link
        case recovery
        case general
    }
    
    enum AnalyticFidoType {
        case general, enroll
    }
    
    enum AnalyticActionType {
        case loggedIn
        case registered
        case loaded
        case click
        case undo
        case cancel
        case cancelFlow
        case fidoRun(type: AnalyticFidoType)
        case fidoNotFinished(type: AnalyticFidoType)
        case fidoFinished(type: AnalyticFidoType)
        case fidoFailed
        case clickContinue
        case wrongOTP(name: String)
        case correctOTP(name: String)
        case resendOTP
        case notYou
        case screenShow(screen: String)
        case userPastedCode
        case webBridge(name: String, type: String)
        case error
        case notNow
        case close
        case enrollSkipped
        case clickEnroll
        case enrollCompleted
        case enrollFailed
        case flowStarted
        case flowEnded
                
        var actionValue: String {
            func fidoActionPrefix(type: AnalyticFidoType) -> String {
                switch type {
                case .general:
                    return ""
                case .enroll:
                    return "[Device Enrollment] - "
                }
            }
            
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
            case .cancelFlow:
                return "User canceled OwnID flow"
            case .fidoRun(let type):
                return "\(fidoActionPrefix(type: type))FIDO: About To Execute"
            case .fidoNotFinished(let type):
                return "\(fidoActionPrefix(type: type))FIDO: Execution Did Not Complete"
            case .fidoFinished(let type):
                return "\(fidoActionPrefix(type: type))FIDO: Execution Completed Successfully"
            case .fidoFailed:
                return "FIDO: Failed, trying to register new one"
            case .clickContinue:
                return "Clicked Continue"
            case .wrongOTP(let name):
                return "[\(name)] - Entered Wrong Verification Code"
            case .correctOTP(let name):
                return "[\(name)] - Entered Correct Verification Code"
            case .resendOTP:
                return "Clicked Resend"
            case .notYou:
                return "Clicked Not You"
            case .screenShow(let screen):
                return "Viewed \(screen)"
            case .userPastedCode:
                return "User Pasted Verification Code"
            case .webBridge(let name, let type):
                return "WebViewBridge: received command [\(name):\(type)]"
            case .error:
                return "Viewed Error"
            case .notNow:
                return "Clicked Not Now"
            case .close:
                return "Clicked Close"
            case .enrollSkipped:
                return "Skipped Device Enrollment"
            case .clickEnroll:
                return "Clicked Enroll Device"
            case .enrollCompleted:
                return "Completed Device Enrollment"
            case .enrollFailed:
                return "Failed Device Enrollment"
            case .flowStarted:
                return "Flow Started"
            case .flowEnded:
                return "Flow Ended"
            }
        }
        
        var isPositionAndTypeAdding: Bool {
            switch self {
            case .loggedIn,
                    .registered,
                    .cancel,
                    .cancelFlow,
                    .fidoRun,
                    .fidoNotFinished,
                    .fidoFinished,
                    .fidoFailed,
                    .clickContinue,
                    .wrongOTP,
                    .correctOTP,
                    .resendOTP,
                    .notYou,
                    .screenShow,
                    .userPastedCode,
                    .webBridge,
                    .error,
                    .notNow,
                    .close,
                    .enrollSkipped,
                    .clickEnroll,
                    .enrollCompleted,
                    .enrollFailed,
                    .flowStarted,
                    .flowEnded:
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
        public var context: String?
        public var component = LoggerConstants.component
        let category: EventCategory
        let type: EventType
        let action: String?
        public var metadata: Metadata?
        let loginId: String?
        let errorMessage: String?
        let errorCode: String?
        let source: String?
        let siteUrl: String?
        let applicationOrigin = Bundle.main.bundleIdentifier
        public var userAgent = UserAgentManager.shared.SDKUserAgent
        public var version = UserAgentManager.shared.version
        public var sourceTimestamp = String(Int((Date().timeIntervalSince1970 * 1000.0).rounded()))
        
        init(context: String? = nil,
             category: EventCategory,
             type: EventType,
             action: String?,
             metadata: Metadata? = nil,
             loginId: String? = nil,
             errorMessage: String? = nil,
             errorCode: String? = nil,
             source: String? = nil,
             siteUrl: String? = nil) {
            self.context = context
            self.category = category
            self.type = type
            self.action = action
            self.metadata = metadata
            self.loginId = loginId
            self.errorMessage = errorMessage
            self.errorCode = errorCode
            self.source = source
            self.siteUrl = siteUrl
        }
        
        private static func metricloginId(_ loginId: String?) -> String? {
            if let loginId, !loginId.isEmpty {
                return SHA256.hash(data: Data((loginId).utf8)).data.toBase64URL()
            }
            return nil
        }
        
        public static func trackMetric(action: AnalyticActionType,
                                       category: EventCategory,
                                       context: String? = nil,
                                       loginId: String? = nil,
                                       loginType: LoginType? = nil,
                                       authType: String? = nil,
                                       source: String? = nil,
                                       siteUrl: String? = nil,
                                       webViewOrigin: String? = nil,
                                       widgetId: String? = nil) -> Metric {
            let metadata = Metadata.metadata(authType: authType,
                                             actionType: action,
                                             loginType: loginType,
                                             webViewOrigin: webViewOrigin,
                                             widgetId: widgetId)
            return Metric(context: context,
                          category: category,
                          type: .track,
                          action: action.actionValue,
                          metadata: metadata,
                          loginId: metricloginId(loginId),
                          source: source,
                          siteUrl: siteUrl)
        }
        
        public static func clickMetric(action: AnalyticActionType,
                                       category: EventCategory,
                                       context: String? = nil,
                                       loginId: String? = nil,
                                       hasLoginId: Bool? = nil,
                                       loginType: LoginType? = nil,
                                       source: String? = nil,
                                       validLoginIdFormat: Bool? = nil) -> Metric {
            Metric(context: context,
                   category: category,
                   type: .click,
                   action: action.actionValue,
                   metadata: Metadata.metadata(actionType: action,
                                               hasLoginId: hasLoginId,
                                               loginType: loginType,
                                               validLoginIdFormat: validLoginIdFormat),
                   loginId: metricloginId(loginId),
                   source: source)
        }
        
        public static func errorMetric(action: AnalyticActionType,
                                       category: EventCategory,
                                       context: String? = nil,
                                       loginId: String? = nil,
                                       loginType: LoginType? = nil,
                                       errorMessage: String?,
                                       errorCode: String? = nil,
                                       source: String? = nil) -> Metric {
            Metric(context: context,
                   category: category,
                   type: .error,
                   action: action.actionValue,
                   metadata: Metadata.metadata(actionType: action, loginType: loginType),
                   loginId: metricloginId(loginId),
                   errorMessage: errorMessage,
                   errorCode: errorCode,
                   source: source)
        }
    }
}
