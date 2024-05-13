import WebKit

protocol WebNameSpace {
    var name: String { set get }
    var actions: [OwnID.CoreSDK.JSAction] { set get }
    
    func invoke(bridgeContext: OwnID.CoreSDK.OwnIDWebBridgeContext,
                action: OwnID.CoreSDK.JSAction,
                params: String,
                metadata: OwnID.CoreSDK.JSMetadata?,
                completion: @escaping (_ result: String) -> Void)
}

extension OwnID.CoreSDK {
    struct JSError: Encodable {
        let error: CoreViewModel.FidoErrorRequestBody.Error
    }
    
    struct OwnIDWebBridgeContext {
        var webView: WKWebView
        var sourceOrigin: URL?
        var allowedOriginRules: [URL]
        var isMainFrame: Bool
    }
    
    final class OwnIDWebBridgeFido: WebNameSpace {
        var name = "FIDO"
        var actions = [JSAction.create, JSAction.get, JSAction.isAvailable]
        
        private var authManager: AuthManager?
        
        private func fidoError(message: String = OwnID.CoreSDK.ErrorMessage.dataIsMissing) -> CoreViewModel.FidoErrorRequestBody.Error {
            let message = OwnID.CoreSDK.ErrorMessage.dataIsMissing
            return CoreViewModel.FidoErrorRequestBody.Error(name: message,
                                                            type: message,
                                                            code: 0,
                                                            message: message)
        }
        
        func invoke(bridgeContext: OwnIDWebBridgeContext,
                    action: OwnID.CoreSDK.JSAction,
                    params: String,
                    metadata: JSMetadata?,
                    completion: @escaping (_ result: String) -> Void) {
            let initialValue = AuthManager.State()
            switch action {
            case .isAvailable:
                completion("\(isPasskeysSupported)")
            case .create, .get:
                guard bridgeContext.isMainFrame else {
                    let message = OwnID.CoreSDK.ErrorMessage.webFrameError
                    completion(handleErrorResult(fidoError: fidoError(message: message)))
                    return
                }
                
                guard bridgeContext.sourceOrigin?.scheme == "https" else {
                    let message = OwnID.CoreSDK.ErrorMessage.webSchemeURLError(urlString: bridgeContext.sourceOrigin?.absoluteString ?? "")
                    completion(handleErrorResult(fidoError: fidoError(message: message)))
                    return
                }
                
                let allowedOrigin = bridgeContext.allowedOriginRules.first { rule in
                    if let sourceHost = bridgeContext.sourceOrigin?.host, let allowHost = rule.host {
                        return sourceHost == allowHost || (allowHost.hasPrefix("*.") && sourceHost.hasSuffix(String(allowHost.dropFirst(2))))
                    }
                    return false
                }
                
                guard allowedOrigin != nil else {
                    let message = OwnID.CoreSDK.ErrorMessage.webSchemeURLError(urlString: bridgeContext.sourceOrigin?.absoluteString ?? "")
                    completion(handleErrorResult(fidoError: fidoError(message: message)))
                    return
                }
                
                guard let jsonData = params.data(using: .utf8),
                      let fidoData = try? JSONDecoder().decode(CoreViewModel.FidoStepData.self, from: jsonData) else {
                    completion(handleErrorResult(fidoError: fidoError()))
                    return
                }
                
                guard let jsonData = params.data(using: .utf8),
                      let paramsJson = try? JSONSerialization.jsonObject(with: jsonData, options : .allowFragments) as? [String: Any],
                      let context = paramsJson["context"] as? String else {
                    completion(handleErrorResult(fidoError: fidoError()))
                    return
                }
                
                let category: EventCategory
                switch metadata?.category ?? .general {
                case .general:
                    category = .general
                case .register:
                    category = .registration
                case .login:
                    category = .login
                case .link:
                    category = .link
                case .recovery:
                    category = .recovery
                }
                
                OwnID.CoreSDK.eventService.sendMetric(.trackMetric(action: .webBridge(type: action.rawValue),
                                                                   category: category,
                                                                   context: metadata?.context,
                                                                   siteUrl: metadata?.siteUrl,
                                                                   webViewOrigin: bridgeContext.sourceOrigin?.absoluteString,
                                                                   widgetId: metadata?.widgetId))
                
                let store = Store(initialValue: initialValue, reducer: reducer(completion: completion))
                
                authManager = AuthManager(store: store, domain: fidoData.rpId, challenge: context)
                if #available(iOS 16.0, *) {
                    if action == .create {
                        authManager?.signUpWith(userName: fidoData.userName, credsIds: fidoData.credsIds)
                    } else if action == .get {
                        authManager?.signIn(credsIds: fidoData.credsIds)
                    }
                }
            }
        }
        
        private func reducer(completion: @escaping (_ result: String) -> Void) -> (inout AuthManager.State, AuthManager.Action) -> [Effect<AuthManager.Action>] {
            let reducer: (inout AuthManager.State, AuthManager.Action) -> [Effect<AuthManager.Action>] = { [weak self] state, action in
                guard let sself = self else { return [] }
                
                switch action {
                case .didFinishLogin(let fido2LoginPayload):
                    guard let jsonData = try? JSONEncoder().encode(fido2LoginPayload),
                          let result = String(data: jsonData, encoding: String.Encoding.utf8) else {
                        completion(sself.handleErrorResult(fidoError: sself.fidoError()))
                        return []
                    }
                    completion(result)
                case .didFinishRegistration(fido2RegisterPayload: let fido2RegisterPayload):
                    guard let jsonData = try? JSONEncoder().encode(fido2RegisterPayload),
                          let result = String(data: jsonData, encoding: String.Encoding.utf8) else {
                        completion(sself.handleErrorResult(fidoError: sself.fidoError()))
                        return []
                    }
                    completion(result)
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
            let JSError = JSError(error: fidoError)
            guard let jsonData = try? JSONEncoder().encode(JSError),
                  let result = String(data: jsonData, encoding: String.Encoding.utf8) else {
                return ""
            }
            
            return result
        }
    }
}
