import SwiftUI
import Combine

/// OwnID class represents core part of SDK. It performs initialization and creates views. It reads OwnIDConfiguration from disk, parses it and loads to memory for later usage. It is a singleton, so the URL returned from outside can be linked to corresponding flow.
public extension OwnID {
    final class CoreSDK {
        public static let shared = CoreSDK()
        public let translationsModule = TranslationsSDK.Manager()
        
        public var currentMetricInformation = OwnID.CoreSDK.CurrentMetricInformation()
        
        @ObservedObject var store: Store<SDKState, SDKAction>
        
        public static var providers: Providers?
        private var flow = OwnID.Flow()
        private var enrollManager = EnrollManager(supportedLanguages: .init(rawValue: []))
        private var socialAuthManager = SocialAuthManager(type: .apple, provider: nil)
        private let redirectPublisher = PassthroughSubject<RedirectEvent, Never>()
        private var activeRedirectContexts: [OwnID.CoreSDK.Context: Int] = [:]
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
                                     supportedLanguages: [String] = Locale.preferredLanguages,
                                     rootURL: String? = nil
        ) {
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
                                             supportedLanguages: .init(rawValue: supportedLanguages),
                                             rootURL: rootURL))
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
            coreViewModel.subscribeToURL(publisher: redirectPublisher.eraseToAnyPublisher())
        }

        var redirectEvents: AnyPublisher<RedirectEvent, Never> {
            redirectPublisher.eraseToAnyPublisher()
        }

        var activeRedirectContextCount: Int {
            activeRedirectContexts.count
        }

        var currentEnrollManager: EnrollManager {
            enrollManager
        }
        
        public static func setSupportedLanguages(_ supportedLanguages: [String]) {
            shared.supportedLanguages = supportedLanguages
            shared.store.send(.updateSupportedLanguages(supportedLanguages: Languages(rawValue: supportedLanguages)))
        }        
        
        static func start(options: EliteOptions?, providers: OwnID.Providers?, eventWrappers: [any FlowWrapper]) {
            shared.flow.start(options: options, providers: providers, eventWrappers: eventWrappers)
        }
        
        public static func startSocialLogin(type: SocialProviderType, provider: SocialProvider? = nil) -> OwnID.SocialEventPublisher {
            let socialAuthManager = SocialAuthManager(type: type, provider: provider)
            shared.socialAuthManager = socialAuthManager
            return shared.socialAuthManager.start()
        }
        
        public static func enrollCredential(loginId: String, authToken: String, force: Bool = false) -> OwnID.EnrollEventPublisher {
            let loginIdPublisher = Just(loginId).eraseToAnyPublisher()
            let authTokenPublisher = Just(authToken).eraseToAnyPublisher()
            return replaceEnrollManager(loginIdPublisher: loginIdPublisher,
                                        authTokenPublisher: authTokenPublisher,
                                        force: force)
        }
        
        public static func enrollCredential(loginIdPublisher: AnyPublisher<String, Never>,
                                            authTokenPublisher: AnyPublisher<String, Never>,
                                            force: Bool = false) -> OwnID.EnrollEventPublisher {
            replaceEnrollManager(loginIdPublisher: loginIdPublisher,
                                 authTokenPublisher: authTokenPublisher,
                                 force: force)
        }

        private static func replaceEnrollManager(
            loginIdPublisher: AnyPublisher<String, Never>,
            authTokenPublisher: AnyPublisher<String, Never>,
            force: Bool
        ) -> OwnID.EnrollEventPublisher {
            if Thread.isMainThread {
                let replacement = prepareEnrollManagerReplacementOnMain(
                    loginIdPublisher: loginIdPublisher,
                    authTokenPublisher: authTokenPublisher,
                    force: force,
                    inputBridges: []
                )
                performEnrollManagerReplacementOnMain(replacement)
                return replacement.publisher
            }

            let loginIdBridge = EnrollManager.InputBridge()
            let authTokenBridge = EnrollManager.InputBridge()
            let replacement = DispatchQueue.main.sync {
                prepareEnrollManagerReplacementOnMain(
                    loginIdPublisher: loginIdBridge.publisher,
                    authTokenPublisher: authTokenBridge.publisher,
                    force: force,
                    inputBridges: [loginIdBridge, authTokenBridge]
                )
            }
            loginIdBridge.connect(to: loginIdPublisher)
            authTokenBridge.connect(to: authTokenPublisher)
            DispatchQueue.main.async {
                performEnrollManagerReplacementOnMain(replacement)
            }
            return replacement.publisher
        }

        private struct EnrollManagerReplacement {
            let previousManager: EnrollManager
            let nextManager: EnrollManager
            let publisher: OwnID.EnrollEventPublisher
        }

        private static func prepareEnrollManagerReplacementOnMain(
            loginIdPublisher: AnyPublisher<String, Never>,
            authTokenPublisher: AnyPublisher<String, Never>,
            force: Bool,
            inputBridges: [EnrollManager.InputBridge]
        ) -> EnrollManagerReplacement {
            assert(Thread.isMainThread)

            let previousManager = shared.enrollManager
            let nextManager = EnrollManager(supportedLanguages: .init(rawValue: shared.supportedLanguages))
            let publisher = nextManager.prepareEnrollment(loginIdPublisher: loginIdPublisher,
                                                          authTokenPublisher: authTokenPublisher,
                                                          force: force,
                                                          inputBridges: inputBridges)
            previousManager.markSuperseded()
            shared.enrollManager = nextManager
            return EnrollManagerReplacement(previousManager: previousManager,
                                            nextManager: nextManager,
                                            publisher: publisher)
        }

        private static func performEnrollManagerReplacementOnMain(_ replacement: EnrollManagerReplacement) {
            assert(Thread.isMainThread)

            replacement.previousManager.cancelForReplacement()
            guard shared.enrollManager === replacement.nextManager else {
                replacement.nextManager.cancelForReplacement()
                return
            }
            replacement.nextManager.startPreparedEnrollment()
        }
        
        func createCoreViewModelForRegister(loginId: String) -> CoreViewModel {
            let viewModel = CoreViewModel(type: .register,
                                          loginId: loginId,
                                          supportedLanguages: store.value.supportedLanguages,
                                          clientConfiguration: store.value.configuration)
            viewModel.subscribeToURL(publisher: redirectPublisher.eraseToAnyPublisher())
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
            viewModel.subscribeToURL(publisher: redirectPublisher.eraseToAnyPublisher())
            viewModel.subscribeToConfiguration(publisher: configurationLoadingEventPublisher.eraseToAnyPublisher())
            return viewModel
        }
        
        /// Used to handle the redirects from browser after webapp is finished
        /// - Parameter url: URL returned from webapp after it has finished
        public func handle(url: URL) {
            onMain { self.routeRedirect(url: url, explicitContext: nil) }
        }

        func handleBrowserCallback(url: URL?, error: Swift.Error?, context: OwnID.CoreSDK.Context) {
            onMain {
                guard self.activeRedirectContexts[context] != nil else {
                    self.logIgnoredRedirect("Ignoring browser callback for inactive context")
                    return
                }
                if let error {
                    let errorModel = UserErrorModel(message: error.localizedDescription)
                    self.redirectPublisher.send(.init(context: context,
                                                      result: .failure(.userError(errorModel: errorModel))))
                } else if let url {
                    if !self.routeRedirect(url: url, explicitContext: context) {
                        let message = OwnID.CoreSDK.ErrorMessage.notValidRedirectionURLOrNotMatchingFromConfiguration
                        self.redirectPublisher.send(.init(
                            context: context,
                            result: .failure(.userError(errorModel: UserErrorModel(message: message)))
                        ))
                    }
                } else {
                    let message = OwnID.CoreSDK.ErrorMessage.requestError
                    self.redirectPublisher.send(.init(context: context,
                                                      result: .failure(.userError(errorModel: UserErrorModel(message: message)))))
                }
            }
        }

        func registerRedirectContext(_ context: OwnID.CoreSDK.Context) {
            onMain { self.activeRedirectContexts[context, default: 0] += 1 }
        }

        func unregisterRedirectContext(_ context: OwnID.CoreSDK.Context) {
            onMain {
                guard let count = self.activeRedirectContexts[context] else { return }
                if count > 1 {
                    self.activeRedirectContexts[context] = count - 1
                } else {
                    self.activeRedirectContexts[context] = nil
                }
            }
        }

        @discardableResult
        private func routeRedirect(url: URL, explicitContext: OwnID.CoreSDK.Context?) -> Bool {
            OwnID.CoreSDK.logger.log(level: .debug, message: "\(url.absoluteString)", type: Self.self)
            guard let redirectionURL = store.value.configuration?.redirectionURL?.lowercased(),
                  url.absoluteString.lowercased().starts(with: redirectionURL) else {
                logIgnoredRedirect(OwnID.CoreSDK.ErrorMessage.notValidRedirectionURLOrNotMatchingFromConfiguration)
                return false
            }

            let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
            let urlContext = queryItems?.first(where: { $0.name == "context" })?.value
            let context = explicitContext ?? urlContext ?? soleActiveRedirectContext
            guard let context, activeRedirectContexts[context] != nil else {
                logIgnoredRedirect("Ignoring redirect with missing or inactive context")
                return false
            }

            if queryItems?.first(where: { $0.name == "redirect" })?.value == "false" {
                let message = OwnID.CoreSDK.ErrorMessage.redirectParameterFromURLCancelledOpeningSDK
                redirectPublisher.send(.init(context: context,
                                             result: .failure(.userError(errorModel: UserErrorModel(message: message)))))
            } else {
                redirectPublisher.send(.init(context: context, result: .success(url)))
            }
            return true
        }

        private var soleActiveRedirectContext: OwnID.CoreSDK.Context? {
            activeRedirectContexts.count == 1 ? activeRedirectContexts.keys.first : nil
        }

        private func logIgnoredRedirect(_ message: String) {
            OwnID.CoreSDK.logger.log(level: .warning, message: message, type: Self.self)
        }

        private func onMain(_ work: @escaping () -> Void) {
            if Thread.isMainThread {
                work()
            } else {
                DispatchQueue.main.async(execute: work)
            }
        }
    }
}

extension OwnID.CoreSDK {
    struct RedirectEvent {
        let context: OwnID.CoreSDK.Context
        let result: Result<URL, OwnID.CoreSDK.Error>
    }
}
