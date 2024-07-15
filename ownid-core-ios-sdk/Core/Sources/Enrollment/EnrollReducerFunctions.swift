import Combine
import Foundation

extension OwnID.CoreSDK.EnrollManager {
    static func fetchLoginId(loginIdPublisher: AnyPublisher<String, Never>) -> [Effect<Action>] {
        let effect = loginIdPublisher
            .handleEvents(receiveOutput: { _ in
                OwnID.CoreSDK.logger.log(level: .debug, message: "LoginId was fetched", type: Self.self)
            })
            .map { loginId in
                return Action.saveLoginId(loginId: loginId)
            }
            .eraseToEffect()
        return [effect]
    }
    
    static func fetchAuthToken(authTokenPublisher: AnyPublisher<String, Never>) -> [Effect<Action>] {
        let effect = authTokenPublisher
            .handleEvents(receiveOutput: { _ in
                OwnID.CoreSDK.logger.log(level: .debug, message: "Token was fetched", type: Self.self)
            })
            .map { authToken in
                return Action.saveAuthToken(authToken: authToken)
            }
            .eraseToEffect()
        return [effect]
    }
    
    static func fetchDisplayName(displayNamePublisher: AnyPublisher<String, Never>) -> [Effect<Action>] {
        let effect = displayNamePublisher
            .handleEvents(receiveOutput: { _ in
                OwnID.CoreSDK.logger.log(level: .debug, message: "Display name was fetched", type: Self.self)
            })
            .map { displayName in
                return Action.saveDisplayName(displayName: displayName)
            }
            .eraseToEffect()
        return [effect]
    }
    
    static func shouldShowView(for loginId: String) -> Bool {
        if let loginIdData = OwnID.CoreSDK.LoginIdDataSaver.loginIdData(from: loginId) {
            guard !loginIdData.isOwnIdLogin else {
                return false
            }
            
            if let interval = loginIdData.lastEnrollmentTimeInterval {
                let notNowDate = Date(timeIntervalSince1970: interval)
                if let days = Calendar.current.dateComponents([.day], from: notNowDate, to: Date()).day {
                    return days >= 7
                }
            }
            return true
        } else {
            return true
        }
    }
    
    static func showView(state: inout State) -> [Effect<Action>] {
        guard let enrollViewStore = state.enrollViewStore, let loginId = state.loginId else {
            let message = OwnID.CoreSDK.ErrorMessage.dataIsMissing
            let errorModel = OwnID.CoreSDK.UserErrorModel(message: message)
            return [Just(.error(OwnID.CoreSDK.ErrorWrapper(error: .userError(errorModel: errorModel), type: Self.self))).eraseToEffect()]
        }
        
        let sourceMetricName = state.sourceMetricName
        OwnID.UISDK.PopupManager.dismissPopup(completion: {
            OwnID.UISDK.showEnrollView(store: enrollViewStore, loginId: loginId, sourceMetricName: sourceMetricName)
        })
        
        return []
    }
    
    static func sendInitRequest(state: inout State) -> [Effect<Action>] {
        let url = state.initURL
        
        let locales = OwnID.CoreSDK.TranslationsSDK.LanguageMapper.matchSystemLanguage(to: OwnID.CoreSDK.shared.supportedLocales ?? [],
                                                                                       userDefinedLanguages: state.supportedLanguages.rawValue)
        let session = OwnID.CoreSDK.SessionService(supportedLanguages: OwnID.CoreSDK.Languages(rawValue: [locales.serverLanguage]))
        state.session = session
        
        let body = AttestationOptions(displayName: state.displayName ?? state.loginId,
                                      username: state.loginId)
        
        let effect = session.perform(url: url,
                                     method: .post,
                                     body: body,
                                     with: FIDOCreateModel.self)
            .receive(on: DispatchQueue.main)
            .handleEvents(receiveOutput: { _ in
                OwnID.CoreSDK.logger.log(level: .debug, message: "Init enrollment request finished", type: Self.self)
            })
            .map({ response in
                OwnID.UISDK.PopupManager.dismissPopup()
                return .fido2Authorize(model: response)
            })
            .catch { Just(Action.error(OwnID.CoreSDK.ErrorWrapper(error: $0, type: Self.self))) }
            .eraseToEffect()
        return [effect]
    }
    
    static func fido2Authorize(state: inout State, model: FIDOCreateModel) {
        let authManager = OwnID.CoreSDK.AuthManager(store: state.authManagerStore,
                                                    domain: model.rp.id,
                                                    challenge: model.challenge)
        state.authManager = authManager
        
        if #available(iOS 16.0, *) {
            OwnID.CoreSDK.eventService.sendMetric(.trackMetric(action: .fidoRun(type: .enroll),
                                                               category: .general,
                                                               loginId: state.loginId,
                                                               source: state.sourceMetricName))
            
            let credsIds = model.excludeCredentials?.map({ $0.id }) ?? []
            authManager.signUpWith(userName: model.user.name, userID: model.user.id, credsIds: credsIds)
        }
    }
    
    static func handleFidoError(state: inout State, error: OwnID.CoreSDK.AuthManager.AuthManagerError) -> [Effect<Action>] {
        let errorMessage: String
        let action: Action
        switch error {
        case .authManagerAuthError(let error), .authManagerGeneralError(let error):
            let error = error as NSError
            errorMessage = error.localizedDescription
            
            let errorModel = OwnID.CoreSDK.UserErrorModel(message: errorMessage)
            action = .error(OwnID.CoreSDK.ErrorWrapper(error: .userError(errorModel: errorModel), type: Self.self))
            
        case .authManagerCredintialsNotFoundOrCanlelledByUser(let error):
            let error = error as NSError
            errorMessage = error.localizedDescription
            action = .cancelled(.fidoRegister)
        default:
            errorMessage = error.errorDescription
            
            let errorModel = OwnID.CoreSDK.UserErrorModel(message: errorMessage)
            action = .error(OwnID.CoreSDK.ErrorWrapper(error: .userError(errorModel: errorModel), type: Self.self))
        }
        
        OwnID.CoreSDK.eventService.sendMetric(.errorMetric(action: .fidoNotFinished(type: .enroll),
                                                           category: .general,
                                                           loginId: state.loginId,
                                                           errorMessage: errorMessage,
                                                           source: state.sourceMetricName))
        
        return [Just(action).eraseToEffect()]
    }
    
    static func sendResultRequest(state: inout State, fido2RegisterPayload: OwnID.CoreSDK.Fido2RegisterPayload) -> [Effect<Action>] {
        let url = state.resultURL
        
        let body = ResultRequestBody(id: fido2RegisterPayload.credentialId,
                                     type: .publicKey,
                                     response: ResultRequestBodyResponse(clientDataJSON: fido2RegisterPayload.clientDataJSON,
                                                                         attestationObject: fido2RegisterPayload.attestationObject))
        
        var headers = URLRequest.defaultHeaders(supportedLanguages: state.supportedLanguages)
        headers["Authorization"] = "Bearer \(state.authToken ?? "")"
        let effect = state.session.perform(url: url,
                                           method: .post,
                                           body: body,
                                           headers: headers,
                                           with: ResultResponse.self)
            .receive(on: DispatchQueue.main)
            .handleEvents(receiveOutput: { _ in
                OwnID.CoreSDK.logger.log(level: .debug, message: "Result enrollment request finished", type: Self.self)
            })
            .map({ response in
                switch response.status {
                case .ok:
                    return .finished(response: response)
                case .failed:
                    let errorModel = OwnID.CoreSDK.UserErrorModel(message: response.errorMessage ?? "")
                    let error = OwnID.CoreSDK.Error.userError(errorModel: errorModel)
                    return .error(OwnID.CoreSDK.ErrorWrapper(error: error, type: Self.self))
                }
            })
            .catch { Just(Action.error(OwnID.CoreSDK.ErrorWrapper(error: $0, type: Self.self))) }
            .eraseToEffect()
        return [effect]
    }
}
