import Foundation
import Combine

extension OwnID.CoreSDK.SocialAuthManager {
    static func reducer(state: inout State, action: Action) -> [Effect<Action>] {
        switch action {
        case .checkProvider:
            checkProvider(state: &state)
            return [Just(.sendInitRequest).eraseToEffect()]
        case .sendInitRequest:
            OwnID.CoreSDK.eventService.sendMetric(.trackMetric(action: .socialStart(type: state.type),
                                                               category: .general,
                                                               source: state.sourceMetricName))
            
            return [sendInitRequest(state: &state)]
        case .login(let clientID, let challengeID):
            state.challengeID = challengeID
            return [login(clientID: clientID, provider: state.provider!)]
        case .sendCompleteRequest(let idToken):
            return [sendCompleteRequest(state: &state, idToken: idToken)]
        case .sendLoginRequest(let accessToken, let loginID):
            return [sendLoginRequest(state: &state, accessToken: accessToken, loginID: loginID)]
        case .error(let wrapper):
            switch wrapper.error {
            case .flowCancelled:
                OwnID.CoreSDK.eventService.sendMetric(.trackMetric(action: .socialCancel(type: state.type),
                                                                   category: .general,
                                                                   source: state.sourceMetricName))
                return [sendCancelRequest(state: &state)]
            case .integrationError:
                OwnID.CoreSDK.eventService.sendMetric(.errorMetric(action: .socialError(type: state.type),
                                                                   category: .general,
                                                                   errorMessage: wrapper.error.errorMessage,
                                                                   source: state.sourceMetricName))
                wrapper.log()
            case .userError(let errorModel):
                OwnID.CoreSDK.eventService.sendMetric(.errorMetric(action: .socialError(type: state.type),
                                                                   category: .general,
                                                                   errorMessage: wrapper.error.errorMessage,
                                                                   source: state.sourceMetricName))
                if errorModel.message.contains("404") {
                    OwnID.CoreSDK.logger.log(level: .warning, message: errorModel.message)
                } else {
                    wrapper.log()
                }
            }
            return []
        case .finish:
            OwnID.CoreSDK.eventService.sendMetric(.trackMetric(action: .socialComplete(type: state.type),
                                                               category: .general,
                                                               source: state.sourceMetricName))
            OwnID.CoreSDK.eventService.sendMetric(.trackMetric(action: .loggedIn,
                                                               category: .general,
                                                               source: state.sourceMetricName))
            return []
        case .end:
            return []
        }
    }
}
