import Foundation

extension OwnID.CoreSDK.SocialAuthManager {
    enum Action {
        case checkProvider
        case sendInitRequest
        case login(clientID: String, challengeID: String)
        case sendCompleteRequest(idToken: String)
        case sendLoginRequest(accessToken: String, loginID: LoginId?)
        case finish(accessToken: String, sessionPayload: String?)
        case error(OwnID.CoreSDK.ErrorWrapper)
        case end
    }
}
