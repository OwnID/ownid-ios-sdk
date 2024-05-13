import Foundation
import Combine

extension OwnID.CoreSDK.EnrollManager {
    static func reducer(state: inout State, action: Action) -> [Effect<Action>] {
        switch action {
        case .addToState(let enrollViewStore, let authManagerStore):
            state.enrollViewStore = enrollViewStore
            state.authManagerStore = authManagerStore
            return []
        case .addPublishers(let loginIdPublisher, let authTokenPublisher, let displayNamePublisher, let force):
            state.loginIdPublisher = loginIdPublisher
            state.authTokenPublisher = authTokenPublisher
            state.displayNamePublisher = displayNamePublisher
            state.force = force
            return [Just(.fetchLoginId).eraseToEffect()]
        case .fetchLoginId:
            return fetchLoginId(loginIdPublisher: state.loginIdPublisher)
        case .saveLoginId(let loginId):
            OwnID.CoreSDK.DefaultsLoginIdSaver.save(loginId: loginId)
            state.loginId = loginId
            return [Just(.fetchAuthToken).eraseToEffect()]
        case .fetchAuthToken:
            return fetchAuthToken(authTokenPublisher: state.authTokenPublisher)
        case .saveAuthToken(let authToken):
            state.authToken = authToken
            return [Just(.fetchDisplayName).eraseToEffect()]
        case .fetchDisplayName:
            return fetchDisplayName(displayNamePublisher: state.displayNamePublisher)
        case .saveDisplayName(let displayName):
            state.displayName = displayName
            return [Just(.showView).eraseToEffect()]
        case .showView:
            if OwnID.CoreSDK.isPasskeysSupported {
                guard !state.force else {
                    return showView(state: &state)
                }
                
                if shouldShowView(for: state.loginId) {
                    return showView(state: &state)
                } else {
                    let message = OwnID.CoreSDK.ErrorMessage.enrollmentSkipped
                    let error = OwnID.CoreSDK.Error.userError(errorModel: OwnID.CoreSDK.UserErrorModel(message: message))
                    return [Just(.skip(error)).eraseToEffect()]
                }
            } else {
                let message = OwnID.CoreSDK.ErrorMessage.fidoUnavailable
                let error = OwnID.CoreSDK.Error.userError(errorModel: OwnID.CoreSDK.UserErrorModel(message: message))
                return [Just(.fidoUnavailable(error)).eraseToEffect()]
            }
        case .skip:
            OwnID.CoreSDK.eventService.sendMetric(.trackMetric(action: .enrollSkipped,
                                                               category: .general,
                                                               loginId: state.loginId,
                                                               source: state.sourceMetricName))
            return []
        case .sendinitRequest:
            return sendInitRequest(state: &state)
        case .fido2Authorize(let model):
            fido2Authorize(state: &state, model: model)
            return []
        case .sendResultRequest(let fido2RegisterPayload):
            return sendResultRequest(state: &state, fido2RegisterPayload: fido2RegisterPayload)
        case .finished:
            OwnID.CoreSDK.eventService.sendMetric(.trackMetric(action: .enrollCompleted,
                                                               category: .general,
                                                               loginId: state.loginId,
                                                               source: state.sourceMetricName))
            return []
        case .enrollView(let action):
            switch action {
            case .viewLoaded:
                return []
            case .cancel:
                return [Just(.cancelled(.enroll)).eraseToEffect()]
            case .continueFlow:
                return [Just(.sendinitRequest).eraseToEffect()]
            case .notNow:
                OwnID.UISDK.PopupManager.dismissPopup()
                OwnID.CoreSDK.logger.log(level: .debug, message: "Skip tapped", type: Self.self)
                let message = OwnID.CoreSDK.ErrorMessage.enrollmentSkipped
                let error = OwnID.CoreSDK.Error.userError(errorModel: OwnID.CoreSDK.UserErrorModel(message: message))
                return [Just(.skip(error)).eraseToEffect()]
            }
        case .authManager(let action):
            switch action {
            case .didFinishLogin:
                break
            case .didFinishRegistration(let fido2RegisterPayload):
                OwnID.CoreSDK.eventService.sendMetric(.trackMetric(action: .fidoFinished(type: .enroll),
                                                                   category: .general,
                                                                   loginId: state.loginId,
                                                                   source: state.sourceMetricName))
                
                return [Just(.sendResultRequest(fido2RegisterPayload: fido2RegisterPayload)).eraseToEffect()]
            case .error(let error, _):
                return handleFidoError(state: &state, error: error)
            }
            return []
        case .fidoUnavailable:
            OwnID.CoreSDK.logger.log(level: .warning, message: "FIDO unavailable", type: Self.self)
            return []
        case .error(let wrapper):
            OwnID.CoreSDK.eventService.sendMetric(.trackMetric(action: .enrollFailed,
                                                               category: .general,
                                                               loginId: state.loginId,
                                                               source: state.sourceMetricName))
            wrapper.log()
            return []
        case .cancelled(let flow):
            switch flow {
            case .fidoRegister:
                OwnID.CoreSDK.eventService.sendMetric(.trackMetric(action: .enrollFailed,
                                                                   category: .general,
                                                                   loginId: state.loginId,
                                                                   source: state.sourceMetricName))
            default:
                break
            }
            
            OwnID.CoreSDK.logger.log(level: .information, message: "Cancel Flow \(flow)", type: Self.self)
            return [Just(.skip(nil)).eraseToEffect()]
        }
    }    
}
