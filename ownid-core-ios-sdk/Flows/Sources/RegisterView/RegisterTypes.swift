import Combine
import Foundation

public extension OwnID {
    typealias RegistrationPublisher = AnyPublisher<Result<OwnID.FlowsSDK.RegistrationEvent, OwnID.CoreSDK.Error>, Never>
    typealias RegistrationResultPublisher = AnyPublisher<OwnID.RegisterResult, OwnID.CoreSDK.Error>
    
    typealias RegistrationFlowPublisher = AnyPublisher<Result<OwnID.FlowsSDK.RegistrationFlowEvent, OwnID.CoreSDK.Error>, Never>
    
    struct RegisterResult {
        public init(operationResult: OperationResult, authType: OwnID.CoreSDK.AuthType? = .none) {
            self.operationResult = operationResult
            self.authType = authType
        }
        
        public let operationResult: OperationResult
        public let authType: OwnID.CoreSDK.AuthType?
    }
}

public extension OwnID.FlowsSDK {
    enum RegistrationEvent {
        case loading
        case resetTapped
        case readyToRegister(loginId: String?, authType: OwnID.CoreSDK.AuthType?)
        case userRegisteredAndLoggedIn(registrationResult: OperationResult, authType: OwnID.CoreSDK.AuthType?)
    }
    
    enum RegistrationFlowEvent {
        case loading
        case resetTapped
        case response(loginId: String, payload: OwnID.CoreSDK.Payload, authType: OwnID.CoreSDK.AuthType?)
    }
    
    struct RegistrationConfiguration {
        public init(payload: OwnID.CoreSDK.Payload,
                    loginId: String) {
            self.payload = payload
            self.loginId = loginId
        }
        
        public let payload: OwnID.CoreSDK.Payload
        public let loginId: String
    }
}

public protocol OperationResult { }

public struct VoidOperationResult: OperationResult {
    public init () { }
}

public protocol RegistrationPerformer {
    func register(configuration: OwnID.FlowsSDK.RegistrationConfiguration, parameters: RegisterParameters) -> OwnID.RegistrationResultPublisher
}
