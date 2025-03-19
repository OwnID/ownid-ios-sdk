import OwnIDCoreSDK
import GoogleSignIn
import Combine

final class GoogleProvider: SocialProvider {
    func login(clientID: String?, viewController: UIViewController?) -> OwnIDCoreSDK.OwnID.SocialResultPublisher {
        guard let clientID, let viewController else {
            let model = OwnID.CoreSDK.UserErrorModel(message: "Google data is missing")
            return Fail(error: .userError(errorModel: model))
                .eraseToAnyPublisher()
        }
        
        let signInConfig = GIDConfiguration(clientID: clientID)
        
        return Future<String, OwnID.CoreSDK.Error> { promise in
            GIDSignIn.sharedInstance.configuration = signInConfig
            GIDSignIn.sharedInstance.signIn(withPresenting: viewController) { signInResult, error in
                guard let signInResult = signInResult, error == nil else {
                    if (error as NSError?)?.code == GIDSignInError.Code.canceled.rawValue {
                        return promise(.failure(.flowCancelled(flow: .socialLogin)))
                    } else {
                        let model = OwnID.CoreSDK.UserErrorModel(message: error?.localizedDescription ?? "")
                        return promise(.failure(.userError(errorModel: model)))
                    }
                }
                
                let idToken = signInResult.user.idToken?.tokenString ?? ""
                
                promise(.success(idToken))
            }
        }
        .eraseToAnyPublisher()
    }
}
