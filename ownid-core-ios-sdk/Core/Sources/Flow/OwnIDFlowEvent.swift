import Foundation

extension OwnID {
    struct FlowEvent: WebBridgeResult {
        let action: FlowAction
        let wrapper: (any FlowWrapper)?
        let payload: FlowPayload?
        
        func runSideEffect() async {
            switch action {
            case .accountRegister, .authenticatePassword, .onAccountNotFound, .onNativeAction, .onFinish, .onClose:
                break
            case .sessionCreate:
                if let payload = payload as? SessionProviderWrapper.Payload {
                    OwnID.CoreSDK.LoginIdSaver.save(loginId: payload.loginId, authMethod: payload.authMethod)
                }
            case .onError:
                if let payload = payload as? OnErrorWrapper.Payload {
                    await OwnID.CoreSDK.logger.log(level: .warning, message: payload.error.errorMessage, type: Self.self)
                    await OwnID.CoreSDK.eventService.sendMetric(.errorMetric(action: .flowError, category: .general, errorMessage: payload.error.errorMessage))
                }
            }
        }
    }
}
