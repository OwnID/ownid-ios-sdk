import AuthenticationServices
import Combine

final class AppleAuthProvider: NSObject, SocialProvider {
    let authenticationAnchor = ASPresentationAnchor()
    private var authController: ASAuthorizationController?
    
    private var resultSubject: PassthroughSubject<String, OwnID.CoreSDK.Error>?
    private var expectedState: String?
    
    func login(clientID: String?, viewController: UIViewController? = nil) -> OwnID.SocialResultPublisher {
        login(
            clientID: clientID,
            viewController: viewController,
            nonce: nil,
            state: Self.makeRequestState()
        )
    }

    func login(
        clientID: String?,
        viewController: UIViewController? = nil,
        nonce: String?,
        state: String
    ) -> OwnID.SocialResultPublisher {
        if #available(iOS 16.0, *) {
            authController?.cancel()
        }
        let subject = PassthroughSubject<String, OwnID.CoreSDK.Error>()
        resultSubject = subject
        expectedState = state
        
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = nonce
        request.state = state
        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = self
        authorizationController.presentationContextProvider = self
        authController = authorizationController
        authorizationController.performRequests()

        return subject.eraseToAnyPublisher()
    }

    static func makeRequestState() -> String {
        Data.generateRandomBytes().base64urlEncodedString()
    }
}

extension AppleAuthProvider: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard controller === authController else { return }

        defer {
            authController = nil
            expectedState = nil
            resultSubject = nil
        }

        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityTokenData = appleIDCredential.identityToken else {
            let errorModel = OwnID.CoreSDK.UserErrorModel(message: "Failed to obtain Apple ID credential data")
            resultSubject?.send(completion: .failure(.userError(errorModel: errorModel)))
            return
        }

        guard appleIDCredential.state == expectedState else {
            let errorModel = OwnID.CoreSDK.UserErrorModel(message: "Apple authorization state mismatch")
            resultSubject?.send(completion: .failure(.userError(errorModel: errorModel)))
            return
        }
        
        let idToken = String(decoding: identityTokenData, as: UTF8.self)
        
        resultSubject?.send(idToken)
        resultSubject?.send(completion: .finished)
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        guard controller === authController else { return }

        defer {
            if #available(iOS 16.0, *) {
                authController?.cancel()
            }
            authController = nil
            expectedState = nil
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
