@_exported import OwnIDCoreSDK
import Combine
import SwiftUI
import Gigya

public extension OwnID.GigyaSDK {
    static let sdkName = "Gigya"
    static let version = "3.6.0"
}

public extension OwnID {
    final class GigyaSDK {        
        public static func info() -> OwnID.CoreSDK.SDKInformation { (sdkName, version) }
        
        /// Standard configuration, searches for default .plist file
        public static func configure(supportedLanguages: [String] = Locale.preferredLanguages) {
            OwnID.CoreSDK.configure(userFacingSDK: info(), supportedLanguages: supportedLanguages)
        }
        
        /// Configures SDK from plist path URL
        public static func configure(plistUrl: URL,
                                     supportedLanguages: [String] = Locale.preferredLanguages) {
            OwnID.CoreSDK.configure(plistUrl: plistUrl,
                                    userFacingSDK: info(),
                                    supportedLanguages: supportedLanguages)
        }
        
        public static func configure(appID: OwnID.CoreSDK.AppID,
                                     redirectionURL: OwnID.CoreSDK.RedirectionURLString? = nil,
                                     environment: String? = nil,
                                     region: String? = nil,
                                     enableLogging: Bool? = nil,
                                     supportedLanguages: [String] = Locale.preferredLanguages) {
            OwnID.CoreSDK.configure(appID: appID,
                                    redirectionURL: redirectionURL,
                                    userFacingSDK: info(),
                                    environment: environment,
                                    region: region,
                                    enableLogging: enableLogging,
                                    supportedLanguages: supportedLanguages)
        }
        
        /// Handles redirects from other flows back to the app
        public static func handle(url: URL) {
            OwnID.CoreSDK.shared.handle(url: url)
        }
        
        // MARK: View Model Flows
        
        /// Creates view model for register flow to manage `OwnID.FlowsSDK.RegisterView`
        /// - Parameters:
        ///   - instance: Instance of Gigya SDK (with custom schema if needed)
        public static func registrationViewModel<T: GigyaAccountProtocol>(instance: GigyaCore<T>,
                                                                          loginIdPublisher: OwnID.CoreSDK.LoginIdPublisher) -> OwnID.FlowsSDK.RegisterView.ViewModel {
            let performer = Registration.Performer(instance: instance)
            let performerLogin = LoginPerformer(instance: instance)
            return OwnID.FlowsSDK.RegisterView.ViewModel(registrationPerformer: performer,
                                                         loginPerformer: performerLogin,
                                                         loginIdPublisher: loginIdPublisher)
        }
        
        public static func createRegisterView(viewModel: OwnID.FlowsSDK.RegisterView.ViewModel,
                                              visualConfig: OwnID.UISDK.VisualLookConfig = .init()) -> OwnID.FlowsSDK.RegisterView {
            OwnID.FlowsSDK.RegisterView(viewModel: viewModel, visualConfig: visualConfig)
        }
        
        /// Creates view model for login flow to manage `OwnID.FlowsSDK.LoginView`
        /// - Parameters:
        ///   - instance: Instance of Gigya SDK (with custom schema if needed)
        public static func loginViewModel<T: GigyaAccountProtocol>(instance: GigyaCore<T>,
                                                                   loginIdPublisher: OwnID.CoreSDK.LoginIdPublisher,
                                                                   loginType: OwnID.CoreSDK.LoginType = .standard) -> OwnID.FlowsSDK.LoginView.ViewModel {
            let performer = LoginPerformer(instance: instance)
            return OwnID.FlowsSDK.LoginView.ViewModel(loginPerformer: performer,
                                                      loginIdPublisher: loginIdPublisher,
                                                      loginType: loginType)
        }
        
        public static func createLoginView(viewModel: OwnID.FlowsSDK.LoginView.ViewModel,
                                           visualConfig: OwnID.UISDK.VisualLookConfig = .init()) -> OwnID.FlowsSDK.LoginView {
            OwnID.FlowsSDK.LoginView(viewModel: viewModel, visualConfig: visualConfig)
        }
        
        public static func gigyaProviders<T: GigyaAccountProtocol>(_ builder: ProvidersBuilder,
                                                                   instance: GigyaCore<T> = Gigya.sharedInstance()) {
            builder.session {
                $0.create { loginId, session, authToken, authMethod in
                    do {
                        let sessionInfoDict = session["sessionInfo"] as? [String: Any] ?? [:]
                        let jsonData = try JSONSerialization.data(withJSONObject: sessionInfoDict)
                        let sessionInfo = try JSONDecoder().decode(SessionInfo.self, from: jsonData)
                        
                        if let session = GigyaSession(sessionToken: sessionInfo.sessionToken,
                                                      secret: sessionInfo.sessionSecret,
                                                      expiration: sessionInfo.expiration) {
                            
                            instance.setSession(session)
                            return .loggedIn
                        } else {
                            return .fail(reason: "error")
                        }
                        
                    } catch {
                        return .fail(reason: error.localizedDescription)
                    }
                }
            }
            
            builder.account {
                $0.register { loginId, profile, ownIdData, authToken in
                    return await withCheckedContinuation { continuation in
                        
                        var registerParams = profile
                        let ownIDParameters = ["ownId": ownIdData]
                        registerParams["data"] = ownIDParameters
                        
                        instance.register(email: loginId,
                                          password: OwnID.FlowsSDK.Password.generatePassword().passwordString,
                                          params: registerParams) { result in
                            switch result {
                            case .success:
                                continuation.resume(returning: .loggedIn)
                            case .failure(let error):
                                continuation.resume(returning: .fail(reason: error.error.localizedDescription))
                            }
                        }
                    }
                }
            }
            
            builder.auth {
                $0.password {
                    $0.authenticate { loginId, password in
                        return await withCheckedContinuation { continuation in
                            instance.login(loginId: loginId, password: password) { result in
                                switch result {
                                case .success:
                                    continuation.resume(returning: .loggedIn)
                                case .failure(let error):
                                    continuation.resume(returning: .fail(reason: error.error.localizedDescription))
                                }
                            }
                        }
                    }
                }
            }
        }

    }
}
