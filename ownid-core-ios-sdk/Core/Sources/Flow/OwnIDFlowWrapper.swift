import Foundation
import Combine

/// A wrapper protocol for functions provided by the customer.
/// This allows for consistent handling and processing of various custom operations.
public protocol FlowWrapper {
    associatedtype PayloadType
    associatedtype R
    func invoke(payload: PayloadType) async -> R
}

protocol FlowPayload { }

extension OwnID {
    struct VoidFlowPayload: FlowPayload {}
    
    struct AccountProviderWrapper: FlowWrapper {
        struct Payload: FlowPayload {
            let loginId: String
            let profile: [String: Any]
            let ownIdData: [String: Any]?
            let authToken: String?
        }
        
        typealias PayloadType = Payload
        typealias R = AuthResult
        
        var provider: AccountProviderProtocol?
        
        func invoke(payload: Payload) async -> AuthResult {
            return await provider?.register(loginId: payload.loginId, 
                                            profile: payload.profile,
                                            ownIdData: payload.ownIdData,
                                            authToken: payload.authToken) ?? .fail(reason: nil)
        }
    }
    
    struct SessionProviderWrapper: FlowWrapper {
        struct Payload: FlowPayload {
            let loginId: String
            let session: [String: Any]
            let authToken: String
            let authMethod: OwnID.CoreSDK.AuthMethod?
        }
        
        typealias PayloadType = Payload
        typealias R = AuthResult
        
        var provider: SessionProviderProtocol?
        
        func invoke(payload: PayloadType) async -> AuthResult {
            return await provider?.create(loginId: payload.loginId,
                                          session: payload.session,
                                          authToken: payload.authToken,
                                          authMethod: payload.authMethod) ?? .fail(reason: nil)
        }
    }
    
    struct AuthPasswordWrapper: FlowWrapper {
        struct Payload: FlowPayload {
            let loginId: String
            let password: String
        }
        
        typealias PayloadType = Payload
        typealias R = AuthResult
        
        var provider: PasswordProviderProtocol?
        
        func invoke(payload: PayloadType) async -> AuthResult {
            return await provider?.authenticate(loginId: payload.loginId, password: payload.password) ?? .fail(reason: nil)
        }
    }
    
    struct OnNativeActionWrapper: FlowWrapper {
        struct Payload: FlowPayload {
            let name: String
            let params: [String: Any]?
        }
        
        typealias PayloadType = Payload
        typealias R = PageAction?
        
        var onNativeAction: ((_ name: String, _ params: [String: Any]?) async -> Void)?
        
        func invoke(payload: PayloadType) async -> R {
            await onNativeAction?(payload.name, payload.params)
            return nil
        }
    }
    
    struct OnAccountNotFoundWrapper: FlowWrapper {
        struct Payload: FlowPayload {
            let loginId: String
            let ownIdData: [String: Any]?
            let authToken: String?
        }
        
        typealias PayloadType = Payload
        typealias R = PageAction?
        
        var onAccountNotFound: ((_ loginId: String, _ ownIdData: [String: Any]?, _ authToken: String?) async -> PageAction)?
        
        func invoke(payload: PayloadType) async -> R {
            return await onAccountNotFound?(payload.loginId, payload.ownIdData, payload.authToken)
        }
    }
    
    struct OnFinishWrapper: FlowWrapper {
        struct Payload: FlowPayload {
            let loginId: String
            let source: String
            let context: String?
            let authMethod: OwnID.CoreSDK.AuthMethod?
            let authToken: String?
        }
        
        typealias PayloadType = Payload
        typealias R = PageAction?
        
        var onFinish: ((_ loginId: String, _ authMethod: OwnID.CoreSDK.AuthMethod?, _ authToken: String?) async -> Void)?
        
        func invoke(payload: PayloadType) async -> R {
            await onFinish?(payload.loginId, payload.authMethod, payload.authToken)
            return nil
        }
    }
    
    struct OnErrorWrapper: FlowWrapper {
        struct Payload: FlowPayload {
            let error: OwnID.CoreSDK.Error
        }
        
        typealias PayloadType = Payload
        typealias R = PageAction?
        
        var onError: ((OwnID.CoreSDK.Error) async -> Void)?
        
        func invoke(payload: PayloadType) async -> R {
            await onError?(payload.error)
            return nil
        }
    }
    
    struct OnCloseWrapper: FlowWrapper {
        typealias PayloadType = VoidFlowPayload
        typealias R = PageAction?
        
        var onClose: (() async -> Void)?
        
        func invoke(payload: PayloadType) async -> R {
            await onClose?()
            return nil
        }
    }
}

extension OwnID {
    /// Represents a result of an OwnID Elite flow event.
    public enum PageAction {
        /// Represents a close action in the OwnID Elite flow. The `onClose` event handler will be called.
        case close
        /// Represents a native action in the OwnID Elite flow. The `onNativeAction` event handler will be called with action name.
        case native(type: PageActionType)
        
        var toString: String {
            var dict: [String: Any] = ["action": action]
            
            switch self {
            case .native(let type):
                dict["name"] = type.name
                dict["params"] = type.params
            case .close:
                break
            }
            
            let jsonData = (try? JSONSerialization.data(withJSONObject: dict)) ?? Data()
            let jsonString = String(data: jsonData, encoding: .utf8)
            return jsonString ?? ""
        }
        
        var action: String {
            switch self {
            case .native:
                return "native"
            case .close:
                return "close"
            }
        }
    }
    
    public enum PageActionType {
        ///Represents a native "register" action in the OwnID Elite flow.
        ///
        /// This action is used to trigger a native registration process, typically when a user's account is not found.
        ///
        /// In response to this action, the `onNativeAction` event handler will be called with the action name "register" and
        /// parameters containing the `loginId`, `ownIdData`, and `authToken` encoded as a JSON string.
        ///
        /// It has parameters:  **loginId** - the user's login identifier, **ownIdData** - optional data associated with the user, **authToken** - optional OwnID authentication token.
        case register(_ loginId: String, _ ownIdData: [String: Any]?, _ authToken: String?)
        
        var name : String {
            switch self {
            case .register:
                return "register"
            }
        }
        
        var params: [String: Any] {
            switch self {
            case .register(let loginId, let ownIdData, let authToken):
                return ["loginId": loginId,
                        "ownIdData": ownIdData ?? "",
                        "authToken": authToken ?? ""]
            }
        }
    }
    
    /// Represents the result of an authentication operation.
    public enum AuthResult: Encodable {
        case fail(reason: String?)
        case loggedIn
        
        var stringValue: String {
            switch self {
            case .loggedIn:
                "logged-in"
            case .fail:
                "fail"
            }
        }
        
        var toString: String {
            var dict = ["status": self.stringValue]
            switch self {
            case .loggedIn:
                break
            case .fail(let reason):
                dict["reason"] = reason
            }
            
            let jsonData = (try? JSONSerialization.data(withJSONObject: dict)) ?? Data()
            let jsonString = String(data: jsonData, encoding: .utf8)
            return jsonString ?? ""
        }
    }
}
