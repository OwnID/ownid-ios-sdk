import SwiftUI
import Combine

/// OwnID class represents core part of SDK. It performs initialization and creates views. It reads OwnIDConfiguration from disk, parses it and loads to memory for later usage. It is a singleton, so the URL returned from outside can be linked to corresponding flow.
public extension OwnID {
    final class CoreSDK {
        public var serverConfigurationURL: ServerURL? { store.value.configuration?.ownIDServerConfigurationURL }
        
        public static let shared = CoreSDK()
        public let translationsModule = TranslationsSDK.Manager()
        
        public var currentMetricInformation = OwnID.CoreSDK.CurrentMetricInformation()
        
        @ObservedObject var store: Store<SDKState, SDKAction>
        
        var providers: Providers?
        private var flow = OwnID.Flow()
        private var enrollManager = EnrollManager(supportedLanguages: .init(rawValue: []))
        private let urlPublisher = PassthroughSubject<Void, OwnID.CoreSDK.Error>()
        private let configurationLoadingEventPublisher = PassthroughSubject<ConfigurationLoadingEvent, Never>()
        private var supportedLanguages = [String]()
        
        private init() {
            let store = Store(
                initialValue: SDKState(configurationLoadingEventPublisher: configurationLoadingEventPublisher),
                reducer: OwnID.CoreSDK.coreReducer
            )
            self.store = store
        }
        
        public var isSDKConfigured: Bool { store.value.configuration != nil }
        
        public static var logger = InternalLogger.shared
        public static var eventService: EventService { EventService.shared }
        
        public func configureForTests() { store.send(.configureForTests) }
        
        public func requestConfiguration() { store.send(.fetchServerConfiguration) }
        
        public static func configure(userFacingSDK: SDKInformation,
                                     underlyingSDKs: [SDKInformation] = [],
                                     supportedLanguages: [String] = Locale.preferredLanguages) {
            if shared.store.value.configurationRequestData == nil {
                shared.supportedLanguages = supportedLanguages
                shared.store.send(.configureFromDefaultConfiguration(userFacingSDK: userFacingSDK,
                                                                     underlyingSDKs: underlyingSDKs,
                                                                     supportedLanguages: .init(rawValue: supportedLanguages)))
            }
        }
        
        public static func configure(appID: OwnID.CoreSDK.AppID,
                                     redirectionURL: RedirectionURLString? = nil,
                                     userFacingSDK: SDKInformation,
                                     underlyingSDKs: [SDKInformation] = [],
                                     environment: String? = nil,
                                     region: String? = nil,
                                     enableLogging: Bool? = nil,
                                     supportedLanguages: [String] = Locale.preferredLanguages) {
            if shared.store.value.configurationRequestData == nil {
                shared.supportedLanguages = supportedLanguages
                shared.store.send(.configure(appID: appID,
                                             redirectionURL: redirectionURL,
                                             userFacingSDK: userFacingSDK,
                                             underlyingSDKs: underlyingSDKs,
                                             isTestingEnvironment: false,
                                             environment: environment,
                                             region: region,
                                             enableLogging: enableLogging,
                                             supportedLanguages: .init(rawValue: supportedLanguages)))
            }
        }
        
        public static func configure(plistUrl: URL,
                                     userFacingSDK: SDKInformation,
                                     underlyingSDKs: [SDKInformation] = [],
                                     supportedLanguages: [String] = Locale.preferredLanguages) {
            if shared.store.value.configurationRequestData == nil {
                shared.supportedLanguages = supportedLanguages
                shared.store.send(.configureFrom(plistUrl: plistUrl,
                                                 userFacingSDK: userFacingSDK,
                                                 underlyingSDKs: underlyingSDKs,
                                                 supportedLanguages: .init(rawValue: supportedLanguages)))
            }
        }
        
        public static func createWebViewBridge(includeNamespaces: [Namespace]? = nil,
                                               excludeNamespaces: [Namespace]? = nil) -> OwnIDWebBridge {
            return OwnIDWebBridge(includeNamespaces: includeNamespaces, excludeNamespaces: excludeNamespaces)
        }
        
        func subscribeForURL(coreViewModel: CoreViewModel) {
            coreViewModel.subscribeToURL(publisher: urlPublisher.eraseToAnyPublisher())
        }
        
        public static func setSupportedLanguages(_ supportedLanguages: [String]) {
            shared.supportedLanguages = supportedLanguages
            shared.store.send(.updateSupportedLanguages(supportedLanguages: Languages(rawValue: supportedLanguages)))
        }        
        
        static func start(providers: OwnID.Providers?, eventWrappers: [any FlowWrapper]) {
            shared.flow.start(providers: providers, eventWrappers: eventWrappers)
        }
        
        public static func enrollCredential(loginId: String, authToken: String, force: Bool = false) -> OwnID.EnrollEventPublisher {
            let enrollManager = EnrollManager(supportedLanguages: .init(rawValue: shared.supportedLanguages))
            shared.enrollManager = enrollManager
            
            let loginIdPublisher = Just(loginId).eraseToAnyPublisher()
            let authTokenPublisher = Just(authToken).eraseToAnyPublisher()
            return shared.enrollManager.enroll(loginIdPublisher: loginIdPublisher,
                                               authTokenPublisher: authTokenPublisher,
                                               force: force)
        }
        
        public static func enrollCredential(loginIdPublisher: AnyPublisher<String, Never>,
                                            authTokenPublisher: AnyPublisher<String, Never>,
                                            force: Bool = false) -> OwnID.EnrollEventPublisher {
            let enrollManager = EnrollManager(supportedLanguages: .init(rawValue: shared.supportedLanguages))
            shared.enrollManager = enrollManager
            
            return shared.enrollManager.enroll(loginIdPublisher: loginIdPublisher,
                                               authTokenPublisher: authTokenPublisher,
                                               force: force)
        }
        
        func createCoreViewModelForRegister(loginId: String) -> CoreViewModel {
            let viewModel = CoreViewModel(type: .register,
                                          loginId: loginId,
                                          supportedLanguages: store.value.supportedLanguages,
                                          clientConfiguration: store.value.configuration)
            viewModel.subscribeToURL(publisher: urlPublisher.eraseToAnyPublisher())
            viewModel.subscribeToConfiguration(publisher: configurationLoadingEventPublisher.eraseToAnyPublisher())
            return viewModel
        }
        
        func createCoreViewModelForLogIn(loginId: String,
                                         loginType: LoginType) -> CoreViewModel {
            let viewModel = CoreViewModel(type: .login,
                                          loginId: loginId,
                                          loginType: loginType,
                                          supportedLanguages: store.value.supportedLanguages,
                                          clientConfiguration: store.value.configuration)
            viewModel.subscribeToURL(publisher: urlPublisher.eraseToAnyPublisher())
            viewModel.subscribeToConfiguration(publisher: configurationLoadingEventPublisher.eraseToAnyPublisher())
            return viewModel
        }
        
        /// Used to handle the redirects from browser after webapp is finished
        /// - Parameter url: URL returned from webapp after it has finished
        public func handle(url: URL) {
            OwnID.CoreSDK.logger.log(level: .debug, message: "\(url.absoluteString)", type: Self.self)
            let redirectParamKey = "redirect"
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
            let redirectParameterValue = components?.first(where: { $0.name == redirectParamKey })?.value
            if redirectParameterValue == "false" {
                let message = OwnID.CoreSDK.ErrorMessage.redirectParameterFromURLCancelledOpeningSDK
                urlPublisher.send(completion: .failure(.userError(errorModel: UserErrorModel(message: message))))
                return
            }
            
            guard let redirection = store.value.configuration,
                  let redirectionUrl = redirection.redirectionURL?.lowercased(),
                  url.absoluteString.lowercased().starts(with: redirectionUrl)
            else {
                let message = OwnID.CoreSDK.ErrorMessage.notValidRedirectionURLOrNotMatchingFromConfiguration
                urlPublisher.send(completion: .failure(.userError(errorModel: UserErrorModel(message: message))))
                return
            }
            urlPublisher.send(())
        }
    }
}
