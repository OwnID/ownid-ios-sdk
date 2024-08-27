import Foundation
import Combine

extension OwnID.CoreSDK {
    static func coreReducer(state: inout SDKState, action: SDKAction) -> [Effect<SDKAction>] {
        switch action {
        case let .configure(appID,
                            redirectionURL,
                            userFacingSDK,
                            underlyingSDKs,
                            isTestingEnvironment,
                            environment,
                            enableLogging,
                            supportedLanguages):
            state.supportedLanguages = supportedLanguages
            OwnID.CoreSDK.logger.log(level: .information, message: "Configuration created", type: Self.self)

            return [createConfiguration(appID: appID,
                                        redirectionURL: redirectionURL,
                                        userFacingSDK: userFacingSDK,
                                        underlyingSDKs: underlyingSDKs,
                                        isTestingEnvironment: isTestingEnvironment,
                                        environment: environment,
                                        enableLogging: enableLogging)]
            
        case let .configurationCreated(configuration, userFacingSDK, underlyingSDKs, isTestingEnvironment):
            if let enableLogging = configuration.enableLogging {
                OwnID.CoreSDK.logger.isEnabled = enableLogging
            }
            state.configurationRequestData = OwnID.CoreSDK.SDKState.ConfigurationRequestData(config: configuration,
                                                                                             userFacingSDK: userFacingSDK,
                                                                                             isLoading: false)
            return [
                Just(.fetchServerConfiguration).eraseToEffect(),
                startLoggerIfNeeded(userFacingSDK: userFacingSDK,
                                    underlyingSDKs: underlyingSDKs,
                                    isTestingEnvironment: isTestingEnvironment),
            ]
            
        case .fetchServerConfiguration:
            guard let configurationRequestData = state.configurationRequestData else {
                let message = OwnID.CoreSDK.ErrorMessage.SDKConfigurationError
                let action = Just(SDKAction.save(configurationLoadingEvent: .error(.userError(errorModel: UserErrorModel(message: message))),
                                                 userFacingSDK: nil))
                return [action.eraseToEffect()]
            }
            if configurationRequestData.isLoading { return [] }
            state.configurationRequestData?.isLoading = true
            return [fetchServerConfiguration(config: configurationRequestData.config,
                                             apiEndpoint: state.apiEndpoint,
                                             userFacingSDK: configurationRequestData.userFacingSDK)]
        case .updateSupportedLanguages(let supportedLanguages):
            state.supportedLanguages = supportedLanguages
            OwnID.CoreSDK.shared.translationsModule.setSupportedLanguages(supportedLanguages)
            return []
        case .configureForTests:
            state.apiEndpoint = .testMock
            OwnID.CoreSDK.logger.isEnabled = true
            return [testConfiguration()]
            
        case let .configureFromDefaultConfiguration(userFacingSDK, underlyingSDKs, supportedLanguages):
            let url = Bundle.main.url(forResource: "OwnIDConfiguration", withExtension: "plist")!
            return [Just(.configureFrom(plistUrl: url, userFacingSDK: userFacingSDK, underlyingSDKs: underlyingSDKs, supportedLanguages: supportedLanguages)).eraseToEffect()]
            
        case let .configureFrom(plistUrl, userFacingSDK, underlyingSDKs, supportedLanguages):
            OwnID.CoreSDK.logger.log(level: .information, message: "Configuration created from plist", type: Self.self)
            
            state.supportedLanguages = supportedLanguages
            return [getDataFrom(plistUrl: plistUrl,
                                userFacingSDK: userFacingSDK,
                                underlyingSDKs: underlyingSDKs,
                                isTestingEnvironment: false)]
            
        case .save(let configurationLoadingEvent, _):
            switch configurationLoadingEvent {
            case .loaded(let config):
                state.configurationRequestData = .none
                state.configuration = config
                state.configurationLoadingEventPublisher.send(configurationLoadingEvent)
                return [
                    translationsDownloaderSDKConfigured(with: state.supportedLanguages),
                    sendLoggerSDKConfigured(),
                    notifyConfigurationFetched()
                ]
                
            case .error:
                state.configurationRequestData?.isLoading = false
                state.configurationLoadingEventPublisher.send(configurationLoadingEvent)
                return []
            }
        }
    }
}
