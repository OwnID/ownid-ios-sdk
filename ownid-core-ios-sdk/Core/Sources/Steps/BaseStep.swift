import Foundation
import Combine

extension OwnID.CoreSDK.CoreViewModel {
    struct StepResponse: Decodable {
        let step: Step?
        let error: ErrorData?
    }
    
    class BaseStep {
        func run(state: inout State) -> [Effect<Action>] { return [] }
        
        func nextStepAction(_ step: Step) -> Action {
            let type = step.type
            switch type {
            case .starting:
                return .idCollect(step: step)
            case .fido2Authorize:
                return .fido2Authorize(step: step)
            case .linkWithCode, .loginIDAuthorization, .verifyLoginID:
                return .oneTimePassword(step: step)
            case .showQr:
                return .webApp(step: step)
            case .success:
                return .success
            }
        }
        
        func errorEffect(_ error: OwnID.CoreSDK.Error,
                         isOnUI: Bool = false,
                         flowFinished: Bool = true,
                         function: String = #function,
                         file: String = #file,
                         type: Any.Type = Any.self) -> [Effect<Action>] {
            [Just(.error(OwnID.CoreSDK.ErrorWrapper(error: error,
                                                    isOnUI: isOnUI,
                                                    flowFinished: flowFinished,
                                                    function: function,
                                                    file: file,
                                                    type: type))).eraseToEffect()]
        }
        
        func handleResponse(response: StepResponse, isOnUI: Bool) -> Action {
            if let step = response.step {
                return nextStepAction(step)
            } else if let errorData = response.error {
                let model = OwnID.CoreSDK.UserErrorModel(code: errorData.errorCode,
                                                         message: errorData.message,
                                                         userMessage: errorData.userMessage)
                return .error(OwnID.CoreSDK.ErrorWrapper(error: .userError(errorModel: model),
                                                         isOnUI: isOnUI,
                                                         flowFinished: errorData.flowFinished ?? true,
                                                         type: Self.self))
            }
            let message = OwnID.CoreSDK.ErrorMessage.requestError
            return .error(OwnID.CoreSDK.ErrorWrapper(error: .userError(errorModel: OwnID.CoreSDK.UserErrorModel(message: message)),
                                                     isOnUI: isOnUI,
                                                     type: Self.self))
        }
    }
}
