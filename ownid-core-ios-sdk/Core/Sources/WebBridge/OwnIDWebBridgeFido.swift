import WebKit

extension OwnID.CoreSDK {
    final class WebBridgeFido: NamespaceHandler {
        var name = Namespace.FIDO
        var actions: [String] = ["isAvailable", "create", "get"]
        
        private var authManager: AuthManager?
        
        private func fidoError(message: String = OwnID.CoreSDK.ErrorMessage.dataIsMissingError()) -> CoreViewModel.FidoErrorRequestBody.Error {
            return CoreViewModel.FidoErrorRequestBody.Error(name: message,
                                                            type: message,
                                                            code: 0,
                                                            message: message)
        }
        
        func invoke(bridgeContext: WebBridgeContext,
                    action: String,
                    params: String,
                    metadata: JSMetadata?,
                    completion: @escaping (_ result: String) -> Void) {
            guard bridgeContext.isMainFrame else {
                let message = OwnID.CoreSDK.ErrorMessage.webFrameError
                completion(handleErrorResult(fidoError: fidoError(message: message)))
                return
            }
            
            switch action {
            case "isAvailable":
                completion("\(isPasskeysSupported)")
            case "create", "get":
                guard isOriginAllowed(bridgeContext.allowedOriginRules, sourceOrigin: bridgeContext.sourceOrigin) else {
                    let message = OwnID.CoreSDK.ErrorMessage.webSchemeURLError(urlString: bridgeContext.sourceOrigin?.absoluteString ?? "")
                    completion(handleErrorResult(fidoError: fidoError(message: message)))
                    return
                }
                
                guard let jsonData = params.data(using: .utf8),
                      let paramsJson = try? JSONSerialization.jsonObject(with: jsonData, options : .allowFragments) as? [String: Any],
                      let context = paramsJson["context"] as? String else {
                    enroll(params: params, completion: completion)
                    return
                }
                
                guard let jsonData = params.data(using: .utf8),
                      let fidoData = try? JSONDecoder().decode(CoreViewModel.FidoStepData.self, from: jsonData) else {
                    completion(handleErrorResult(fidoError: fidoError()))
                    return
                }
                
                let store = Store(initialValue: AuthManager.State(), reducer: reducer(isEnroll: false, completion: completion))
                
                authManager = AuthManager(store: store, domain: fidoData.rpId, challenge: context)
                if #available(iOS 16.0, *) {
                    if action == "create" {
                        authManager?.signUpWith(userName: fidoData.userName, credsIds: fidoData.credsIds)
                    } else if action == "get" {
                        authManager?.signIn(credsIds: fidoData.credsIds)
                    }
                }
            default:
                break
            }
        }
        
        private func isOriginAllowed(_ allowedOriginRules: [URL], sourceOrigin: URL?) -> Bool {
            if allowedOriginRules.map({ $0.absoluteString }).contains("*") { return true }

            let allowedOrigin = allowedOriginRules.first { rule in
                if let sourceHost = sourceOrigin?.host, let allowHost = rule.host, let sourceScheme = sourceOrigin?.scheme, let allowScheme = rule.scheme {
                    return sourceHost.lowercased() == allowHost.lowercased() && sourceScheme.lowercased() == allowScheme.lowercased()
                }
                
                return false
            }
            
            return allowedOrigin != nil
        }
        
        private func enroll(params: String,
                            completion: @escaping (_ result: String) -> Void) {
            guard let jsonData = params.data(using: .utf8),
                  let fidoData = try? JSONDecoder().decode(EnrollManager.FIDOCreateModel.self, from: jsonData) else {
                completion(handleErrorResult(fidoError: fidoError()))
                return
            }
            
            let store = Store(initialValue: AuthManager.State(), reducer: reducer(isEnroll: true, completion: completion))

            authManager = OwnID.CoreSDK.AuthManager(store: store,
                                                    domain: fidoData.rp.id,
                                                    challenge: fidoData.challenge)
            
            if #available(iOS 16.0, *) {
                let credsIds = fidoData.excludeCredentials?.map({ $0.id }) ?? []
                authManager?.signUpWith(userName: fidoData.user.name, userID: fidoData.user.id, credsIds: credsIds)
            }
        }
        
        private func reducer(isEnroll: Bool, completion: @escaping (_ result: String) -> Void) -> (inout AuthManager.State, AuthManager.Action) -> [Effect<AuthManager.Action>] {
            let reducer: (inout AuthManager.State, AuthManager.Action) -> [Effect<AuthManager.Action>] = { [weak self] state, action in
                guard let sself = self else { return [] }
                
                func handleResult(model: Encodable, completion: @escaping (_ result: String) -> Void) {
                    guard let jsonData = try? JSONEncoder().encode(model),
                          let result = String(data: jsonData, encoding: String.Encoding.utf8) else {
                        completion(sself.handleErrorResult(fidoError: sself.fidoError()))
                        return
                    }
                    completion(result)
                }
                
                switch action {
                case .didFinishLogin(let fido2LoginPayload):
                    handleResult(model: fido2LoginPayload, completion: completion)
                case .didFinishRegistration(fido2RegisterPayload: let fido2RegisterPayload):
                    if isEnroll {
                        let response = EnrollManager.ResultRequestBodyResponse(clientDataJSON: fido2RegisterPayload.clientDataJSON,
                                                                               attestationObject: fido2RegisterPayload.attestationObject)
                        let model = EnrollManager.ResultRequestBody(id: fido2RegisterPayload.credentialId,
                                                                    type: .publicKey,
                                                                    response: response)
                        handleResult(model: model, completion: completion)
                    } else {
                        handleResult(model: fido2RegisterPayload, completion: completion)
                    }
                case .error(let error, _):
                    completion(sself.handleErrorResult(fidoError: sself.error(error)))
                }
                return []
            }
            
            return reducer
        }
        
        private func error(_ error: AuthManager.AuthManagerError) -> CoreViewModel.FidoErrorRequestBody.Error {
            let fidoError: CoreViewModel.FidoErrorRequestBody.Error
            
            switch error {
            case .authManagerAuthError(let error), .authManagerGeneralError(let error):
                let error = error as NSError
                fidoError = CoreViewModel.FidoErrorRequestBody.Error(name: error.domain,
                                                                     type: error.domain,
                                                                     code: 0,
                                                                     message: error.localizedDescription)
            case .authManagerCredintialsNotFoundOrCanlelledByUser(let error):
                let error = error as NSError
                fidoError = CoreViewModel.FidoErrorRequestBody.Error(name: error.domain,
                                                                     type: error.domain,
                                                                     code: 0,
                                                                     message: error.localizedDescription)
            default:
                fidoError = CoreViewModel.FidoErrorRequestBody.Error(name: error.errorDescription,
                                                                     type: error.errorDescription,
                                                                     code: 0,
                                                                     message: error.errorDescription)
            }
            
            return fidoError
        }
        
        private func handleErrorResult(fidoError: CoreViewModel.FidoErrorRequestBody.Error) -> String {
            let error = JSError(error: OwnID.CoreSDK.JSErrorData(type: fidoError.type,
                                                                 errorMessage: fidoError.message,
                                                                 errorCode: "\(fidoError.code)"))
            
            guard let jsonData = try? JSONEncoder().encode(error),
                  let result = String(data: jsonData, encoding: String.Encoding.utf8) else {
                return ""
            }
            
            return result
        }
    }
}
