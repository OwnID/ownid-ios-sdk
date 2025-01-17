import Foundation
import Combine

extension OwnID.CoreSDK.EnrollManager {
    enum Action {
        case addToState(enrollViewStore: Store<OwnID.UISDK.Enroll.ViewState, OwnID.UISDK.Enroll.Action>,
                        authStore: Store<OwnID.CoreSDK.AuthManager.State, OwnID.CoreSDK.AuthManager.Action>)
        case addPublishers(loginIdPublisher: AnyPublisher<String, Never>,
                           authTokenPublisher: AnyPublisher<String, Never>,
                           force: Bool)
        case checkPasskeysSupported
        case fetchLoginId
        case checkLoginId(loginId: String)
        case saveLoginId(loginId: String)
        case fetchAuthToken
        case saveAuthToken(authToken: String)
        case sendInitRequest
        case checkCredentials(model: FIDOCreateModel)
        case saveFidoModel(model: FIDOCreateModel)
        case showView
        case fido2Authorize
        case sendResultRequest(fido2RegisterPayload: OwnID.CoreSDK.Fido2RegisterPayload)
        case finished(response: ResultResponse)
        case enrollView(OwnID.UISDK.Enroll.Action)
        case authManager(OwnID.CoreSDK.AuthManager.Action)
        case fidoUnavailable(OwnID.CoreSDK.Error)
        case error(OwnID.CoreSDK.ErrorWrapper)
        case cancelled(OwnID.CoreSDK.FlowType)
        case skip(OwnID.CoreSDK.Error?)
    }
}
