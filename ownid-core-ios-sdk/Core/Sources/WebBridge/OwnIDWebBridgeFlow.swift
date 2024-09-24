import WebKit
import Combine

extension OwnID.CoreSDK {
    enum WebBridgeFlowError: Swift.Error {
        case wrongData
    }
}

extension OwnID.CoreSDK.WebBridgeFlowError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .wrongData:
            return OwnID.CoreSDK.ErrorMessage.dataIsMissingError()
        }
    }
}
    
extension OwnID.CoreSDK {
    final class WebBridgeFlow: NamespaceHandler {
        var name = Namespace.FLOW
        var actions: [String] = []
        
        static let shared = WebBridgeFlow()
        
        private var wrappers = [any FlowWrapper]()
        
        func invoke(bridgeContext: WebBridgeContext,
                    action: String,
                    params: String,
                    metadata: JSMetadata?,
                    completion: @escaping (_ result: String) -> Void) {
            if let flowAction = OwnID.FlowAction(rawValue: action) {
                do {
                    let jsonData = params.data(using: .utf8) ?? Data()
                    let authDict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] ?? [:]
                    
                    switch flowAction {
                    case .accountRegister:
                        guard let loginId = authDict["loginId"] as? String,
                              let profile = authDict["profile"] as? [String: Any] else {
                            throw WebBridgeFlowError.wrongData
                        }
                        
                        let ownIdData = authDict["ownIdData"] as? [String: Any]
                        let authToken = authDict["authToken"] as? String
                        let payload = OwnID.AccountProviderWrapper.Payload(loginId: loginId,
                                                                           profile: profile,
                                                                           ownIdData: ownIdData,
                                                                           authToken: authToken)
                        let wrapper: OwnID.AccountProviderWrapper? = OwnID.wrapperByAction(flowAction, wrappers: wrappers)
                        let flowEvent = OwnID.FlowEvent(action: flowAction, wrapper: wrapper, payload: payload)
                        
                        Task {
                            await flowEvent.runSideEffect()
                            let result = await wrapper?.invoke(payload: payload)
                            completion(result?.toString ?? "{}")
                        }
                    case .sessionCreate:
                        let metadata = authDict["metadata"] as? [String: Any] ?? [:]
                        
                        guard let loginId = metadata["loginId"] as? String,
                              let authToken = metadata["authToken"] as? String,
                              let session = authDict["session"] as? [String: Any] else {
                            throw WebBridgeFlowError.wrongData
                        }
                        
                        let authType = AuthType(rawValue: metadata["authType"] as? String ?? "")
                        let payload = OwnID.SessionProviderWrapper.Payload(loginId: loginId,
                                                                     session: session,
                                                                     authToken: authToken,
                                                                     authMethod: AuthMethod.authMethod(from: authType))
                        let wrapper: OwnID.SessionProviderWrapper? = OwnID.wrapperByAction(flowAction, wrappers: wrappers)
                        let flowEvent = OwnID.FlowEvent(action: flowAction, wrapper: wrapper, payload: payload)
                        
                        Task {
                            await flowEvent.runSideEffect()
                            let result = await wrapper?.invoke(payload: payload)
                            completion(result?.toString ?? "{}")
                        }
                    case .authenticatePassword:
                        guard let loginId = authDict["loginId"] as? String,
                              let password = authDict["password"] as? String else {
                            throw WebBridgeFlowError.wrongData
                        }
                        
                        let payload = OwnID.AuthPasswordWrapper.Payload(loginId: loginId, password: password)
                        let wrapper: OwnID.AuthPasswordWrapper? = OwnID.wrapperByAction(flowAction, wrappers: wrappers)
                        let flowEvent = OwnID.FlowEvent(action: flowAction, wrapper: wrapper, payload: payload)
                        
                        Task {
                            await flowEvent.runSideEffect()
                            let result = await wrapper?.invoke(payload: payload)
                            completion(result?.toString ?? "{}")
                        }
                    case .onAccountNotFound:
                        guard let loginId = authDict["loginId"] as? String else {
                            throw WebBridgeFlowError.wrongData
                        }
                        
                        let authToken = authDict["authToken"] as? String
                        let ownIdData = authDict["ownIdData"] as? String
                        let payload = OwnID.OnAccountNotFoundWrapper.Payload(loginId: loginId, ownIdData: ownIdData, authToken: authToken)
                        let wrapper: OwnID.OnAccountNotFoundWrapper? = OwnID.wrapperByAction(flowAction, wrappers: wrappers)
                        let flowEvent = OwnID.FlowEvent(action: flowAction, wrapper: wrapper, payload: payload)
                        
                        Task {
                            await flowEvent.runSideEffect()
                            let result = await wrapper?.invoke(payload: payload)
                            completion(result?.toString ?? "{}")
                        }
                    case .onFinish:
                        guard let loginId = authDict["loginId"] as? String,
                              let source = authDict["source"] as? String else {
                            throw WebBridgeFlowError.wrongData
                        }
                        
                        let contextDict = authDict["context"] as? [String: Any] ?? [:]
                        let context = contextDict["context"] as? String
                        let authType = AuthType(rawValue: authDict["authType"] as? String ?? "")
                        let authToken = authDict["authToken"] as? String
                        let payload = OwnID.OnFinishWrapper.Payload(loginId: loginId,
                                                              source: source,
                                                              context: context,
                                                              authMethod: AuthMethod.authMethod(from: authType),
                                                              authToken: authToken)
                        let wrapper: OwnID.OnFinishWrapper? = OwnID.wrapperByAction(flowAction, wrappers: wrappers)
                        let flowEvent = OwnID.FlowEvent(action: flowAction, wrapper: wrapper, payload: payload)
                        
                        Task {
                            await flowEvent.runSideEffect()
                            bridgeContext.resultPublisher?.send(flowEvent)
                        }
                    case .onError:
                        let authDict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] ?? [:]
                        let errorModel: UserErrorModel
                        if let code = authDict["errorCode"] as? String,
                           let message = authDict["errorMessage"] as? String {
                            errorModel = UserErrorModel(code: code, message: message, userMessage: nil)
                        } else {
                            errorModel = UserErrorModel(message: params)
                        }
                        
                        let payload = OwnID.OnErrorWrapper.Payload(error: .userError(errorModel: errorModel))
                        let wrapper: OwnID.OnErrorWrapper? = OwnID.wrapperByAction(flowAction, wrappers: wrappers)
                        let flowEvent = OwnID.FlowEvent(action: flowAction, wrapper: wrapper, payload: payload)
                        
                        Task {
                            await flowEvent.runSideEffect()
                            bridgeContext.resultPublisher?.send(flowEvent)
                        }
                    case .onClose:
                        let wrapper: OwnID.OnCloseWrapper? = OwnID.wrapperByAction(flowAction, wrappers: wrappers)
                        let flowEvent = OwnID.FlowEvent(action: flowAction, wrapper: wrapper, payload: OwnID.VoidFlowPayload())
                        
                        Task {
                            await flowEvent.runSideEffect()
                            bridgeContext.resultPublisher?.send(flowEvent)
                        }
                    }
                    
                } catch {
                    let errorModel = UserErrorModel(message: error.localizedDescription)
                    handleError(bridgeContext: bridgeContext, errorModel: errorModel)
                }
            } else {
                let errorModel = UserErrorModel(message: WebBridgeFlowError.wrongData.localizedDescription)
                handleError(bridgeContext: bridgeContext, errorModel: errorModel)
            }
        }
        
        func sendTerminalAction(flowEvent: OwnID.FlowEvent) {
            Task {
                switch flowEvent.action {
                case .onClose:
                    if let wrapper = flowEvent.wrapper as? OwnID.OnCloseWrapper,
                       let payload = flowEvent.payload as? OwnID.OnCloseWrapper.PayloadType {
                        await _ = wrapper.invoke(payload: payload)
                    }
                case .onError:
                    if let wrapper = flowEvent.wrapper as? OwnID.OnErrorWrapper,
                       let payload = flowEvent.payload as? OwnID.OnErrorWrapper.Payload {
                        await _ = wrapper.invoke(payload: payload)
                    }
                case .onFinish:
                    if let wrapper = flowEvent.wrapper as? OwnID.OnFinishWrapper,
                       let payload = flowEvent.payload as? OwnID.OnFinishWrapper.PayloadType {
                        await _ = wrapper.invoke(payload: payload)
                    }
                default:
                    let errorModel = UserErrorModel(message: "Action is not terminal")
                    ErrorWrapper(error: .userError(errorModel: errorModel), type: Self.self).log()
                }
            }
        }
        
        func setWrappers(_ wrappers: [any FlowWrapper]) {
            self.wrappers = wrappers
            
            wrappers.forEach { wrapper in
                if let action = OwnID.FlowAction.allCases.first(where: { $0.wrapperType == type(of: wrapper) }) {
                    actions.append(action.rawValue)
                }
            }
        }
        
        private func handleError(bridgeContext: WebBridgeContext, errorModel: OwnID.CoreSDK.UserErrorModel) {
            let payload = OwnID.OnErrorWrapper.Payload(error: .userError(errorModel: errorModel))
            let wrapper: OwnID.OnErrorWrapper? = OwnID.wrapperByAction(.onError, wrappers: wrappers)
            let flowEvent = OwnID.FlowEvent(action: .onError, wrapper: wrapper, payload: payload)
            bridgeContext.resultPublisher?.send(flowEvent)
            
            ErrorWrapper(error: .userError(errorModel: errorModel), type: Self.self).log()
        }
    }
}
