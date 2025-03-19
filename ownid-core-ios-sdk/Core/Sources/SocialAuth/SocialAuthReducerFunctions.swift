import Combine
import Foundation
import UIKit

extension OwnID.CoreSDK.SocialAuthManager {
    static func checkProvider(state: inout State) {
        switch state.type {
        case .google:
            let provider: SocialProvider = state.provider ?? OwnID.CoreSDK.providers?.google?.googleProvider ?? {
                let providerName = "GoogleProvider"
                guard let providerClass = NSClassFromString("\(Bundle.appName()).\(providerName)")
                        as? SocialProvider.Type else {
                    fatalError("Google provider is not set")
                }
                return providerClass.init()
            }()
            
            print(provider)
            state.provider = provider
        case .apple:
            state.provider = AppleAuthProvider()
        }
    }
    
    static func sendInitRequest(state: inout State) -> Effect<Action> {
        let session = OwnID.CoreSDK.SessionService()
        state.session = session
        
        let url = state.initURL(type: state.type)
        let body = InitRequestBody(oauthResponseType: .idToken)
        let effect = state.session.perform(url: url,
                                           method: .post,
                                           body: body,
                                           with: InitResponse.self)
            .receive(on: DispatchQueue.main)
            .handleEvents(receiveOutput: { _ in
                OwnID.CoreSDK.logger.log(level: .debug, message: "Social init request finished", type: Self.self)
            })
            .map({ response in
                return .login(clientID: response.clientId, challengeID: response.challengeId)
            })
            .catch { Just(Action.error(OwnID.CoreSDK.ErrorWrapper(error: $0, type: Self.self))) }
            .eraseToEffect()
        return effect
    }
    
    
    static func login(clientID: String, provider: SocialProvider) -> Effect<Action> {
        return provider.login(clientID: clientID, viewController: UIApplication.topViewController())
            .map({ response in
                OwnID.CoreSDK.logger.log(level: .debug, message: "TokenID was fetched", type: Self.self)
                return .sendCompleteRequest(idToken: response)
            })
            .catch { Just(Action.error(OwnID.CoreSDK.ErrorWrapper(error: $0, type: Self.self))) }
            .eraseToEffect()
    }
    
    static func sendCompleteRequest(state: inout State, idToken: String) -> Effect<Action> {
        let url = state.resultURL
        let body = CompleteRequestBody(challengeId: state.challengeID, idToken: idToken)
        let effect = state.session.perform(url: url,
                                           method: .post,
                                           body: body,
                                           with: CompleteResponse.self)
            .receive(on: DispatchQueue.main)
            .handleEvents(receiveOutput: { _ in
                OwnID.CoreSDK.logger.log(level: .debug, message: "Social result request finished", type: Self.self)
            })
            .map({ response in
                return .sendLoginRequest(accessToken: response.accessToken, loginID: response.loginId)
            })
            .catch { Just(Action.error(OwnID.CoreSDK.ErrorWrapper(error: $0, type: Self.self))) }
            .eraseToEffect()
        return effect
    }
    
    static func sendLoginRequest(state: inout State, accessToken: String, loginID: LoginId?) -> Effect<Action> {
        let url = state.loginURL
        var headers = URLRequest.defaultHeaders(supportedLanguages: OwnID.CoreSDK.Languages.init(rawValue: []))
        headers["Authorization"] = "Bearer \(accessToken)"
        let body = LoginRequestBody(loginId: loginID)
        let effect = state.session.perform(url: url,
                                           method: .post,
                                           body: body,
                                           headers: headers)
            .receive(on: DispatchQueue.main)
            .handleEvents(receiveOutput: { _ in
                OwnID.CoreSDK.logger.log(level: .debug, message: "Social login request finished", type: Self.self)
            })
            .map({ response in
                let sessionPayload = response["sessionPayload"] as? [String: Any] ?? [:]
                let data = (try? JSONSerialization.data(withJSONObject: sessionPayload)) ?? Data()
                let payloadString = String(data: data, encoding: .utf8)
                return .finish(accessToken: accessToken, sessionPayload: payloadString)
            })
            .catch { Just(Action.error(OwnID.CoreSDK.ErrorWrapper(error: $0, type: Self.self))) }
            .eraseToEffect()
        return effect
    }
    
    static func sendCancelRequest(state: inout State) -> Effect<Action> {
        let url = state.cancelURL
        let body = CancelRequestBody(challengeId: state.challengeID)
        let effect = state.session.perform(url: url,
                                           method: .post,
                                           body: body)
            .map({ response in
                return .end
            })
            .catch { _ in Just(Action.end) }
            .eraseToEffect()
        return effect
    }
}
