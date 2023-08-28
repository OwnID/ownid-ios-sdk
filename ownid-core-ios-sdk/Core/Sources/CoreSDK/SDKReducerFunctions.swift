import Combine

extension OwnID.CoreSDK {
    static func getDataFrom(plistUrl: URL,
                            userFacingSDK: SDKInformation,
                            underlyingSDKs: [SDKInformation],
                            isTestingEnvironment: Bool) -> Effect<SDKAction> {
        let data = try! Data(contentsOf: plistUrl)
        let decoder = PropertyListDecoder()
        let config = try! decoder.decode(OwnID.CoreSDK.LocalConfiguration.self, from: data)
        let action = SDKAction.configurationCreated(configuration: config,
                                                    userFacingSDK: userFacingSDK,
                                                    underlyingSDKs: underlyingSDKs,
                                                    isTestingEnvironment: isTestingEnvironment)
        return Just(action).eraseToEffect()
    }
    
    static func testConfiguration() -> Effect<SDKAction> {
        let action = SDKAction.configure(appID: "gephu5k2dnff2v",
                                         redirectionURL: "com.ownid.demo.gigya://ownid/redirect/",
                                         userFacingSDK: (OwnID.CoreSDK.sdkName, OwnID.CoreSDK.version),
                                         underlyingSDKs: [],
                                         isTestingEnvironment: true,
                                         environment: .none,
                                         supportedLanguages: .init(rawValue: Locale.preferredLanguages))
        return Just(action).eraseToEffect()
    }
    
    static func createConfiguration(appID: OwnID.CoreSDK.AppID,
                                    redirectionURL: RedirectionURLString,
                                    userFacingSDK: SDKInformation,
                                    underlyingSDKs: [SDKInformation],
                                    isTestingEnvironment: Bool,
                                    environment: String?) -> Effect<SDKAction> {
        let config = try! OwnID.CoreSDK.LocalConfiguration(appID: appID,
                                                           redirectionURL: redirectionURL,
                                                           environment: environment)
        return Just(.configurationCreated(configuration: config,
                                          userFacingSDK: userFacingSDK,
                                          underlyingSDKs: underlyingSDKs,
                                          isTestingEnvironment: isTestingEnvironment))
        .eraseToEffect()
    }
    
    static func startLoggerIfNeeded(userFacingSDK: SDKInformation,
                                    underlyingSDKs: [SDKInformation],
                                    isTestingEnvironment: Bool) -> Effect<SDKAction> {
        .fireAndForget {
            OwnID.CoreSDK.UserAgentManager.shared.registerUserFacingSDKName(userFacingSDK, underlyingSDKs: underlyingSDKs)
            OwnID.CoreSDK.logger.log(level: .debug, OwnID.CoreSDK.self)
        }
    }
    
    static func fetchServerConfiguration(config: LocalConfiguration,
                                             apiEndpoint: APIEndpoint,
                                         userFacingSDK: OwnID.CoreSDK.SDKInformation) -> Effect<SDKAction> {
        let effect = Deferred {
            apiEndpoint.serverConfiguration(config.ownIDServerConfigurationURL)
                .map { serverConfiguration in
                    if let logLevel = serverConfiguration.logLevel {
                        OwnID.CoreSDK.logger.updateLogLevel(logLevel: logLevel)
                        OwnID.CoreSDK.logger.log(level: .information, message: "Log level set to \(logLevel)", Self.self)
                    } else {
                        OwnID.CoreSDK.logger.updateLogLevel(logLevel: .warning)
                        OwnID.CoreSDK.logger.log(level: .warning, message: "Server configuration is not set", force: true, Self.self)
                    }
                    var local = config
                    local.serverURL = serverConfiguration.serverURL
                    local.redirectionURL = (serverConfiguration.platformSettings?.redirectUrlOverride ?? serverConfiguration.redirectURLString) ?? local.redirectionURL
                    local.passkeysAutofillEnabled = serverConfiguration.passkeysAutofillEnabled
                    local.supportedLocales = serverConfiguration.supportedLocales
                    local.loginIdSettings = serverConfiguration.loginIdSettings
                    local.enableRegistrationFromLogin = serverConfiguration.enableRegistrationFromLogin
                    return SDKAction.save(configurationLoadingEvent: .loaded(local), userFacingSDK: userFacingSDK)
                }
                .catch { _ in
                    OwnID.CoreSDK.logger.updateLogLevel(logLevel: .warning)
                    OwnID.CoreSDK.logger.log(level: .warning, message: "Server configuration is not set", force: true, Self.self)
                    let message = OwnID.CoreSDK.ErrorMessage.noServerConfig
                    return Just(SDKAction.save(configurationLoadingEvent: .error(.userError(errorModel: UserErrorModel(message: message))),
                                               userFacingSDK: userFacingSDK))
                }
        }
        return effect.eraseToEffect()
    }
    
    static func translationsDownloaderSDKConfigured(with supportedLanguages: OwnID.CoreSDK.Languages) -> Effect<SDKAction> {
        .fireAndForget {
            OwnID.CoreSDK.shared.translationsModule.SDKConfigured(supportedLanguages: supportedLanguages)
            OwnID.CoreSDK.logger.log(level: .debug, OwnID.CoreSDK.self)
        }
    }
    
    static func sendLoggerSDKConfigured() -> Effect<SDKAction> {
        .fireAndForget {
            OwnID.CoreSDK.logger.sdkConfigured()
        }
    }
}
