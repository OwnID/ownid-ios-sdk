import Foundation
import Combine

extension OwnID.CoreSDK.CoreViewModel {
    struct AuthRequestBody: Encodable {
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(type, forKey: .type)
            if let fido2Payload = fido2Payload as? OwnID.CoreSDK.Fido2LoginPayload {
                try container.encode(fido2Payload, forKey: .result)
            }
            if let fido2Payload = fido2Payload as? OwnID.CoreSDK.Fido2RegisterPayload {
                try container.encode(fido2Payload, forKey: .result)
            }
        }
        
        let type: OwnID.CoreSDK.RequestType
        let fido2Payload: Encodable
        
        enum CodingKeys: CodingKey {
            case type
            case result
        }
    }
    
    struct FidoErrorRequestBody: Encodable {
        let type: OwnID.CoreSDK.RequestType
        let error: Error
        
        struct Error: Encodable {
            let name: String
            let type: String
            let code: Int
            let message: String
        }
    }
    
    class FidoAuthStep: BaseStep {
        private let step: Step
        private var type = OwnID.CoreSDK.RequestType.register
        
        init(step: Step) {
            self.step = step
        }
        
        override func run(state: inout State) -> [Effect<OwnID.CoreSDK.CoreViewModel.Action>] {
            let eventCategory: OwnID.CoreSDK.EventCategory = state.type == .login ? .login : .registration
            OwnID.CoreSDK.logger.log(level: .debug, message: "run Fido \(type.rawValue)", type: Self.self)
            OwnID.CoreSDK.eventService.sendMetric(.trackMetric(action: .fidoRun(type: .general),
                                                               category: eventCategory,
                                                               context: state.context,
                                                               loginId: state.loginId))
            if #available(iOS 16, *),
               let domain = step.fidoData?.rpId {
                let authManager = OwnID.CoreSDK.AuthManager(store: state.authManagerStore,
                                                            domain: domain,
                                                            challenge: state.context)
                if let operation = step.fidoData?.operation {
                    let credsIds = step.fidoData?.credsIds ?? []
                    switch operation {
                    case .login:
                        if credsIds.isEmpty {
                            let message = "Login failed - no credentials specified, trying to register new one"
                            OwnID.CoreSDK.logger.log(level: .warning, message: message, type: Self.self)
                            OwnID.CoreSDK.eventService.sendMetric(.trackMetric(action: .fidoFailed,
                                                                               category: eventCategory,
                                                                               context: state.context,
                                                                               loginId: state.loginId))
                            authManager.signUpWith(userName: state.loginId, credsIds: credsIds)
                        } else {
                            authManager.signIn(credsIds: credsIds)
                        }
                    case .register:
                        authManager.signUpWith(userName: state.loginId, credsIds: credsIds)
                    }
                }
                
                state.authManager = authManager
            }
            
            return []
        }
        
        func sendAuthRequest(state: inout OwnID.CoreSDK.CoreViewModel.State,
                             fido2Payload: Encodable,
                             type: OwnID.CoreSDK.RequestType) -> [Effect<Action>] {
            guard let urlString = step.fidoData?.url, let url = URL(string: urlString) else {
                let message = OwnID.CoreSDK.ErrorMessage.dataIsMissingError(dataInfo: "url")
                return errorEffect(.userError(errorModel: OwnID.CoreSDK.UserErrorModel(message: message)), type: Self.self)
            }

            self.type = type
            let context = state.context
            let eventCategory: OwnID.CoreSDK.EventCategory = state.type == .login ? .login : .registration
            
            OwnID.CoreSDK.eventService.sendMetric(.trackMetric(action: .fidoFinished(type: .general),
                                                               category: eventCategory,
                                                               context: context,
                                                               loginId: state.loginId))
            
            let requestBody = AuthRequestBody(type: type,
                                              fido2Payload: fido2Payload)
            let effect = state.session.perform(url: url,
                                               method: .post,
                                               body: requestBody,
                                               with: StepResponse.self)
                .receive(on: DispatchQueue.main)
                .handleEvents(receiveOutput: { response in
                    OwnID.CoreSDK.logger.log(level: .debug, message: "Auth Request Finished", type: Self.self)
                })
                .map { [self] in handleResponse(response: $0, isOnUI: false) }
                .catch { Just(Action.error(OwnID.CoreSDK.ErrorWrapper(error: $0, type: Self.self))) }
                .eraseToEffect()
            
            return [effect]
        }
        
        func handleFidoError(state: inout OwnID.CoreSDK.CoreViewModel.State,
                             error: OwnID.CoreSDK.AuthManager.AuthManagerError) -> [Effect<Action>] {
            guard let urlString = step.fidoData?.url, let url = URL(string: urlString) else {
                let message = OwnID.CoreSDK.ErrorMessage.dataIsMissingError(dataInfo: "url")
                return errorEffect(.userError(errorModel: OwnID.CoreSDK.UserErrorModel(message: message)), type: Self.self)
            }
            
            let fidoError: OwnID.CoreSDK.CoreViewModel.FidoErrorRequestBody.Error
            let errorMessage: String
            switch error {
            case .authManagerAuthError(let error), .authManagerGeneralError(let error):
                let error = error as NSError
                fidoError = OwnID.CoreSDK.CoreViewModel.FidoErrorRequestBody.Error(name: error.domain,
                                                                                   type: error.domain,
                                                                                   code: error.code,
                                                                                   message: error.localizedDescription)
                errorMessage = error.localizedDescription
            case .authManagerCredintialsNotFoundOrCanlelledByUser(let error):
                let error = error as NSError
                fidoError = OwnID.CoreSDK.CoreViewModel.FidoErrorRequestBody.Error(name: error.domain,
                                                                                   type: error.domain,
                                                                                   code: error.code,
                                                                                   message: error.localizedDescription)
                errorMessage = error.localizedDescription
            default:
                fidoError = OwnID.CoreSDK.CoreViewModel.FidoErrorRequestBody.Error(name: error.errorDescription,
                                                                                   type: error.errorDescription,
                                                                                   code: 0,
                                                                                   message: error.errorDescription)
                errorMessage = error.errorDescription
            }
            
            let eventCategory: OwnID.CoreSDK.EventCategory = state.type == .login ? .login : .registration
            let context = state.context
            OwnID.CoreSDK.eventService.sendMetric(.errorMetric(action: .fidoNotFinished(type: .general),
                                                               category: eventCategory,
                                                               context: context,
                                                               loginId: state.loginId,
                                                               errorMessage: errorMessage))
            
            let requestBody = FidoErrorRequestBody(type: type,
                                                   error: fidoError)
            let effect = state.session.perform(url: url,
                                               method: .post,
                                               body: requestBody,
                                               with: StepResponse.self)
                .receive(on: DispatchQueue.main)
                .handleEvents(receiveOutput: { response in
                    OwnID.CoreSDK.logger.log(level: .debug, message: "Error Request Finished", type: Self.self)
                })
                .map { [self] in handleResponse(response: $0, isOnUI: false) }
                .catch { Just(Action.error(OwnID.CoreSDK.ErrorWrapper(error: $0, type: Self.self))) }
                .eraseToEffect()
            return [effect]
        }
    }
}
