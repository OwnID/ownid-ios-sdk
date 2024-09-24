import Foundation

extension OwnID {
    enum FlowAction: String, CaseIterable {
        case accountRegister = "account_register"
        case sessionCreate = "session_create"
        case authenticatePassword = "auth_password_authenticate"
        case onAccountNotFound
        case onFinish
        case onError
        case onClose
        
        var isTerminal: Bool {
            switch self {
            case .accountRegister, .sessionCreate, .authenticatePassword, .onAccountNotFound:
                return false
            case .onFinish, .onError, .onClose:
                return true
            }
        }
        
        var wrapperType: Any.Type {
            switch self {
            case .accountRegister:
                return AccountProviderWrapper.self
            case .sessionCreate:
                return SessionProviderWrapper.self
            case .authenticatePassword:
                return AuthPasswordWrapper.self
            case .onAccountNotFound:
                return OnAccountNotFoundWrapper.self
            case .onFinish:
                return OnFinishWrapper.self
            case .onError:
                return OnErrorWrapper.self
            case .onClose:
                return OnCloseWrapper.self
            }
        }
    }
    
    static func wrapperByAction<T: FlowWrapper>(_ action: OwnID.FlowAction, wrappers: [any FlowWrapper]) -> T? {
        return wrappers.first(where: { action.wrapperType == type(of: $0) }) as? T
    }
}
