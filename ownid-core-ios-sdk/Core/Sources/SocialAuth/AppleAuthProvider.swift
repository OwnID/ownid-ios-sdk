import AuthenticationServices
import Combine

final class AppleAuthProvider: NSObject, SocialProvider {
    let authenticationAnchor = ASPresentationAnchor()
    private var authController: ASAuthorizationController?
    
    private var resultSubject: PassthroughSubject<String, OwnID.CoreSDK.Error>?
    
    func login(clientID: String?, viewController: UIViewController? = nil) -> OwnID.SocialResultPublisher {
        if #available(iOS 16.0, *) {
            authController?.cancel()
        }
        let subject = PassthroughSubject<String, OwnID.CoreSDK.Error>()
        resultSubject = subject
        
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = self
        authorizationController.presentationContextProvider = self
        authorizationController.performRequests()
        
        return subject.eraseToAnyPublisher()
    }
}

extension AppleAuthProvider: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityTokenData = appleIDCredential.identityToken else {
            let errorModel = OwnID.CoreSDK.UserErrorModel(message: "Failed to obtain Apple ID credential data")
            resultSubject?.send(completion: .failure(.userError(errorModel: errorModel)))
            resultSubject = nil
            return
        }
        
        let idToken = String(decoding: identityTokenData, as: UTF8.self)
        
        resultSubject?.send(idToken)
        resultSubject?.send(completion: .finished)
        resultSubject = nil
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        defer {
            if #available(iOS 16.0, *) {
                authController?.cancel()
            }
            resultSubject = nil
        }
        
        guard let authorizationError = error as? ASAuthorizationError else {
            let errorModel = OwnID.CoreSDK.UserErrorModel(message: error.localizedDescription)
            resultSubject?.send(completion: .failure(.userError(errorModel: errorModel)))
            return
        }
        
        if authorizationError.code == .canceled {
            resultSubject?.send(completion: .failure(.flowCancelled(flow: .socialLogin)))
        } else {
            let errorModel = OwnID.CoreSDK.UserErrorModel(message: error.localizedDescription)
            resultSubject?.send(completion: .failure(.userError(errorModel: errorModel)))
        }
    }
}

extension AppleAuthProvider: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        authenticationAnchor
    }
}
