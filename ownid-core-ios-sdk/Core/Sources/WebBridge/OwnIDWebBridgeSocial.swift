import WebKit
import Combine

extension OwnID.CoreSDK {
    final class WebBridgeSocial: NamespaceHandler {
        struct JSSocialInfo: Codable {
            let clientId: String?
            let challengeId: String?
        }
        
        struct JSError: Codable {
            let error: JSErrorData
        }
        
        struct JSErrorData: Codable {
            let name: String?
            let type: String?
            let message: String?
        }
        
        var name = Namespace.SOCIAL
        var actions: [String] = ["Google", "Apple"]
        private let appleProvider = AppleAuthProvider()
        
        private var bag = Set<AnyCancellable>()
        
        func invoke(bridgeContext: WebBridgeContext,
                    action: String,
                    params: String,
                    metadata: JSMetadata?,
                    completion: @escaping (_ result: String) -> Void) {
            guard bridgeContext.isMainFrame else {
                let message = OwnID.CoreSDK.ErrorMessage.webFrameError
                completion(handleErrorResult(type: "OwnIdWebViewBridgeSocialError", message: message))
                return
            }
            
            let jsonData = params.data(using: .utf8) ?? Data()
            guard let socialInfo = try? JSONDecoder().decode(JSSocialInfo.self, from: jsonData),
                  (socialInfo.clientId ?? "").isEmpty == false,
                  (socialInfo.challengeId ?? "").isEmpty == false else {
                let message = OwnID.CoreSDK.ErrorMessage.dataIsMissingError()
                completion(handleErrorResult(type: "OwnIdWebViewBridgeSocialError", message: message))
                return
            }
            
            switch action {
            case "Google":
                let provider: SocialProvider = OwnID.CoreSDK.providers?.google?.googleProvider ?? {
                    let providerName = "GoogleProvider"
                    guard let providerClass = NSClassFromString("\(Bundle.appName()).\(providerName)")
                            as? SocialProvider.Type else {
                        fatalError("Google provider is not set")
                    }
                    return providerClass.init()
                }()
                
                provider.login(clientID: socialInfo.clientId, viewController: UIApplication.topViewController())
                    .sink(receiveCompletion: { [weak self] receivedCompletion in
                        switch receivedCompletion {
                        case .finished:
                            break
                        case .failure(let error):
                            let errorType: String
                            switch error {
                            case .flowCancelled:
                                errorType = "OwnIdCancellationException"
                            default:
                                errorType = "OwnIdWebViewBridgeSocialError"
                            }
                            let message = error.localizedDescription
                            completion(self?.handleErrorResult(type: errorType, message: message) ?? "{}")
                        }
                    }, receiveValue: { idToken in
                        completion("'\(idToken)'")
                    })
                    .store(in: &bag)
            case "Apple":
                appleProvider.login(clientID: nil)
                    .sink(receiveCompletion: { [weak self] receivedCompletion in
                        switch receivedCompletion {
                        case .finished:
                            break
                        case .failure(let error):
                            let errorType: String
                            switch error {
                            case .flowCancelled:
                                errorType = "OwnIdCancellationException"
                            default:
                                errorType = "OwnIdWebViewBridgeSocialError"
                            }
                            let message = error.localizedDescription
                            completion(self?.handleErrorResult(type: errorType, message: message) ?? "{}")
                        }
                    }, receiveValue: { idToken in
                        completion("'\(idToken)'")
                    })
                    .store(in: &bag)
            default:
                break
            }
        }
        
        private func handleErrorResult(type: String, message: String) -> String {
            let error = JSError(error: JSErrorData(name: name.rawValue,
                                                   type: type,
                                                   message: message))
            
            guard let jsonData = try? JSONEncoder().encode(error),
                  let errorString = String(data: jsonData, encoding: String.Encoding.utf8) else {
                return "{}"
            }
            return errorString
        }
    }
}
