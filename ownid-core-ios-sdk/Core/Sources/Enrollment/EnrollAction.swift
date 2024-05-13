import Foundation
import Combine

extension OwnID.CoreSDK.EnrollManager {
    enum Action {
        case addToState(enrollViewStore: Store<OwnID.UISDK.Enroll.ViewState, OwnID.UISDK.Enroll.Action>,
                        authStore: Store<OwnID.CoreSDK.AuthManager.State, OwnID.CoreSDK.AuthManager.Action>)
        case addPublishers(loginIdPublisher: AnyPublisher<String, Never>,
                           authTokenPublisher: AnyPublisher<String, Never>,
                           displayNamePublisher: AnyPublisher<String, Never>,
                           force: Bool)
        case fetchLoginId
        case saveLoginId(loginId: String)
        case fetchAuthToken
        case saveAuthToken(authToken: String)
        case fetchDisplayName
        case saveDisplayName(displayName: String?)
        case showView
        case skip(OwnID.CoreSDK.Error?)
        case sendinitRequest
        case fido2Authorize(model: FIDOCreateModel)
        case sendResultRequest(fido2RegisterPayload: OwnID.CoreSDK.Fido2RegisterPayload)
        case finished(response: ResultResponse)
        case enrollView(OwnID.UISDK.Enroll.Action)
        case authManager(OwnID.CoreSDK.AuthManager.Action)
        case fidoUnavailable(OwnID.CoreSDK.Error)
        case error(OwnID.CoreSDK.ErrorWrapper)
        case cancelled(OwnID.CoreSDK.FlowType)
    }
}
