import Foundation
import Combine

extension OwnID.CoreSDK.EnrollManager {
    static func reducer(state: inout State, action: Action) -> [Effect<Action>] {
        switch action {
        case .addToState(let enrollViewStore, let authManagerStore):
            state.enrollViewStore = enrollViewStore
            state.authManagerStore = authManagerStore
            return []
        case .addPublishers(let loginIdPublisher, let authTokenPublisher, let force):
            state.loginIdPublisher = loginIdPublisher
            state.authTokenPublisher = authTokenPublisher
            state.force = force
            return [Just(.checkPasskeysSupported).eraseToEffect()]
        case .checkPasskeysSupported:
            if OwnID.CoreSDK.isPasskeysSupported {
                return [Just(.fetchLoginId).eraseToEffect()]
            } else {
                let message = OwnID.CoreSDK.ErrorMessage.fidoUnavailable
                let error = OwnID.CoreSDK.Error.userError(errorModel: OwnID.CoreSDK.UserErrorModel(message: message))
                return [Just(.fidoUnavailable(error)).eraseToEffect()]
            }
        case .fetchLoginId:
            return fetchLoginId(loginIdPublisher: state.loginIdPublisher)
        case .checkLoginId(let loginId):
            if shouldShowView(for: loginId, force: state.force) {
                return [Just(.saveLoginId(loginId: loginId)).eraseToEffect()]
            } else {
                let message = OwnID.CoreSDK.ErrorMessage.enrollmentSkipped
                let error = OwnID.CoreSDK.Error.userError(errorModel: OwnID.CoreSDK.UserErrorModel(message: message))
                return [Just(.skip(error)).eraseToEffect()]
            }
        case .saveLoginId(let loginId):
            state.loginId = loginId
            return [Just(.fetchAuthToken).eraseToEffect()]
        case .fetchAuthToken:
            return fetchAuthToken(authTokenPublisher: state.authTokenPublisher)
        case .saveAuthToken(let authToken):
            state.authToken = authToken
            return [Just(.sendinitRequest).eraseToEffect()]
        case .sendinitRequest:
            return sendInitRequest(state: &state)
        case .checkCredentials(let model):
            if shouldShowView(for: model, force: state.force) {
                return [Just(.saveFidoModel(model: model)).eraseToEffect()]
            } else {
                OwnID.CoreSDK.LoginIdSaver.save(loginId: state.loginId, authMethod: .passkey)
                
                let message = OwnID.CoreSDK.ErrorMessage.enrollmentSkipped
                let error = OwnID.CoreSDK.Error.userError(errorModel: OwnID.CoreSDK.UserErrorModel(message: message))
                return [Just(.skip(error)).eraseToEffect()]
            }
        case .saveFidoModel(let model):
            state.fidoCreateModel = model
            return [Just(.showView).eraseToEffect()]
        case .showView:
            return showView(state: &state)
        case .skip:
            OwnID.CoreSDK.eventService.sendMetric(.trackMetric(action: .enrollSkipped,
                                                               category: .general,
                                                               loginId: state.loginId,
                                                               source: state.sourceMetricName))
            return []
        case .fido2Authorize:
            fido2Authorize(state: &state)
            return []
        case .sendResultRequest(let fido2RegisterPayload):
            return sendResultRequest(state: &state, fido2RegisterPayload: fido2RegisterPayload)
        case .finished:
            OwnID.CoreSDK.eventService.sendMetric(.trackMetric(action: .enrollCompleted,
                                                               category: .general,
                                                               loginId: state.loginId,
                                                               source: state.sourceMetricName))
            OwnID.CoreSDK.LoginIdSaver.save(loginId: state.loginId, authMethod: .passkey)
            return []
        case .enrollView(let action):
            switch action {
            case .viewLoaded:
                return []
            case .cancel:
                return [Just(.cancelled(.enroll)).eraseToEffect()]
            case .continueFlow:
                OwnID.UISDK.PopupManager.dismissPopup()
                return [Just(.fido2Authorize).eraseToEffect()]
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
