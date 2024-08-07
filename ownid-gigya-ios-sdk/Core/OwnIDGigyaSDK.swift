@_exported import OwnIDCoreSDK
import Combine
import SwiftUI
import Gigya

public extension OwnID.GigyaSDK {
    static let sdkName = "Gigya"
    static let version = "3.3.1"
}

public extension OwnID {
    final class GigyaSDK {
        
        // MARK: Setup
        
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
                                     enableLogging: Bool? = nil,
                                     supportedLanguages: [String] = Locale.preferredLanguages) {
            OwnID.CoreSDK.configure(appID: appID,
                                    redirectionURL: redirectionURL,
                                    userFacingSDK: info(),
                                    environment: environment,
                                    enableLogging: enableLogging,
                                    supportedLanguages: supportedLanguages)
        }
        
        public static func defaultLoginIdPublisher<T: GigyaAccountProtocol>(instance: GigyaCore<T>) -> AnyPublisher<String, Never> {
            Future<String, Never> { promise in
                instance.getAccount(true) { result in
                    if case let .success(data) = result {
                        promise(.success(data.profile?.email ?? ""))
                    }
                }
            }
            .eraseToAnyPublisher()
        }
        
        public static func defaultAuthTokenPublisher<T: GigyaAccountProtocol>(instance: GigyaCore<T>) -> AnyPublisher<String, Never> {
            Future<String, Never> { promise in
                instance.send(api: "accounts.getJWT") { result in
                    if case let .success(data) = result {
                        let authToken = data["id_token"]?.value as? String ?? ""
                        promise(.success(authToken))
                    }
                }
            }
            .eraseToAnyPublisher()
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
    }
}
