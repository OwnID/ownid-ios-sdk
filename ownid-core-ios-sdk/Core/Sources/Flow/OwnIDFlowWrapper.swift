import Foundation
import Combine

/// A wrapper protocol for functions provided by the customer.
/// This allows for consistent handling and processing of various custom operations.
public protocol FlowWrapper {
    associatedtype PayloadType
    associatedtype R: Encodable
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
    
    struct OnAccountNotFoundWrapper: FlowWrapper {
        struct Payload: FlowPayload {
            let loginId: String
            let ownIdData: String?
            let authToken: String?
        }
        
        typealias PayloadType = Payload
        typealias R = PageAction
        
        var onAccountNotFoundClosure: ((_ loginId: String, _ ownIdData: String?, _ authToken: String?) async -> PageAction)?
        
        func invoke(payload: PayloadType) async -> PageAction {
            return await onAccountNotFoundClosure?(payload.loginId, payload.ownIdData, payload.authToken) ?? .none
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
        typealias R = PageAction
        
        var onFinish: ((_ loginId: String, _ authMethod: OwnID.CoreSDK.AuthMethod?, _ authToken: String?) async -> Void)?
        
        func invoke(payload: PayloadType) async -> PageAction {
            await onFinish?(payload.loginId, payload.authMethod, payload.authToken)
            return PageAction.none
        }
    }
    
    struct OnErrorWrapper: FlowWrapper {
        struct Payload: FlowPayload {
            let error: OwnID.CoreSDK.Error
        }
        
        typealias PayloadType = Payload
        typealias R = PageAction
        
        var onError: ((OwnID.CoreSDK.Error) async -> Void)?
        
        func invoke(payload: PayloadType) async -> PageAction {
            await onError?(payload.error)
            return PageAction.none
        }
    }
    
    struct OnCloseWrapper: FlowWrapper {
        typealias PayloadType = VoidFlowPayload
        typealias R = PageAction
        
        var onClose: (() async -> Void)?
        
        func invoke(payload: PayloadType) async -> PageAction {
            await onClose?()
            return PageAction.none
        }
    }
}

extension OwnID {
    /// Represents a result of an OwnID Elite flow event.
    public enum PageAction: String, Encodable {
        case none
        
        var toString: String {
            let dict = ["action": self.rawValue]
            let jsonData = (try? JSONSerialization.data(withJSONObject: dict)) ?? Data()
            let jsonString = String(data: jsonData, encoding: .utf8)
            return jsonString ?? ""
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
