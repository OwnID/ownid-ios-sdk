@_exported import OwnIDCoreSDK
import Combine
import SwiftUI
import Gigya

public extension OwnID.GigyaSDK {
    static let sdkName = "Gigya"
    static let version = "1.0.1"
}

public extension OwnID {
    final class GigyaSDK {
        
        // MARK: Setup
        
        public static func info() -> OwnID.CoreSDK.SDKInformation {
            (sdkName, version)
        }
        
        /// Standart configuration, searches for default .plist file
        public static func configure() {
            OwnID.CoreSDK.shared.configure(userFacingSDK: info(), underlyingSDKs: [])
        }
        
        /// Configures SDK from URL
        /// - Parameter plistUrl: Config plist URL
        public static func configure(plistUrl: URL) {
            OwnID.CoreSDK.shared.configureFor(plistUrl: plistUrl, userFacingSDK: info(), underlyingSDKs: [])
        }
        
        /// Configures SDK from parameters
        /// - Parameters:
        ///   - serverURL: ServerURL
        ///   - redirectionURL: RedirectionURL
        public static func configure(appID: String, redirectionURL: String, environment: String? = .none) {
            OwnID.CoreSDK.shared.configure(appID: appID,
                                           redirectionURL: redirectionURL,
                                           userFacingSDK: info(),
                                           underlyingSDKs: [],
                                           environment: environment)
        }
        
        /// Used to handle the redirects from browser after webapp is finished
        /// - Parameter url: URL returned from webapp after it has finished
        public static func handle(url: URL) {
            OwnID.CoreSDK.shared.handle(url: url, sdkConfigurationName: sdkName)
        }
        
        // MARK: View Model Flows
        
        /// Creates view model for register flow in Gigya and manages ``OwnID.FlowsSDK.RegisterView``
        /// - Parameters:
        ///   - instance: Instance of Gigya SDK (with custom schema if needed)
        ///   - webLanguages: Languages for web view. List of well-formed [IETF BCP 47 language tag](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Accept-Language) .
        /// - Returns: View model for register flow
        public static func registrationViewModel<T: GigyaAccountProtocol>(instance: GigyaCore<T>,
                                                                          webLanguages: OwnID.CoreSDK.Languages = .init(rawValue: Locale.preferredLanguages),
                                                                          sdkName: String = sdkName) -> OwnID.FlowsSDK.RegisterView.ViewModel {
            let performer = Registration.Performer(instance: instance, sdkConfigurationName: sdkName)
            let performerLogin = LoginPerformer(instance: instance,
                                                sdkConfigurationName: sdkName)
            return OwnID.FlowsSDK.RegisterView.ViewModel(registrationPerformer: performer,
                                                         loginPerformer: performerLogin,
                                                         sdkConfigurationName: sdkName,
                                                         webLanguages: webLanguages)
        }
        
        /// View that encapsulates management of ``OwnID.SkipPasswordView`` state
        /// - Parameter viewModel: ``OwnID.FlowsSDK.RegisterView.ViewModel``
        /// - Parameter email: email to be used in link on login and displayed when loggin in
        /// - Parameter visualConfig: contains information about how views will look like
        /// - Returns: View to display
        public static func createRegisterView(viewModel: OwnID.FlowsSDK.RegisterView.ViewModel,
                                              email: Binding<String>,
                                              visualConfig: OwnID.UISDK.VisualLookConfig = .init()) -> OwnID.FlowsSDK.RegisterView {
            OwnID.FlowsSDK.RegisterView(viewModel: viewModel,
                                        usersEmail: email,
                                        visualConfig: visualConfig)
        }
        
        /// Creates view model for log in flow in Gigya and manages ``OwnID.FlowsSDK.RegisterView``
        /// - Parameters:
        ///   - instance: Instance of Gigya SDK (with custom schema if needed)
        ///   - webLanguages: Languages for web view. List of well-formed [IETF BCP 47 language tag](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Accept-Language) .
        /// - Returns: View model for log in
        public static func loginViewModel<T: GigyaAccountProtocol>(instance: GigyaCore<T>,
                                                                   loginType: OwnID.CoreSDK.LoginType = .standard,
                                                                   webLanguages: OwnID.CoreSDK.Languages = .init(rawValue: Locale.preferredLanguages),
                                                                   sdkName: String = sdkName) -> OwnID.FlowsSDK.LoginView.ViewModel {
            let performer = LoginPerformer(instance: instance,
                                           sdkConfigurationName: sdkName)
            return OwnID.FlowsSDK.LoginView.ViewModel(loginPerformer: performer,
                                                      sdkConfigurationName: sdkName,
                                                      loginType: loginType,
                                                      webLanguages: webLanguages)
        }
        
        /// View that encapsulates management of ``OwnID.SkipPasswordView`` state
        /// - Parameter viewModel: ``OwnID.LoginView.ViewModel``
        /// - Parameter usersEmail: Email to be used in link on login and displayed when loggin in
        /// - Parameter visualConfig: contains information about how views will look like
        /// - Returns: View to display
        public static func createLoginView(viewModel: OwnID.FlowsSDK.LoginView.ViewModel,
                                           usersEmail: Binding<String>,
                                           visualConfig: OwnID.UISDK.VisualLookConfig = .init()) -> OwnID.FlowsSDK.LoginView {
            OwnID.FlowsSDK.LoginView(viewModel: viewModel,
                                     usersEmail: usersEmail,
                                     visualConfig: visualConfig)
        }
    }
}
