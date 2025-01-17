import Foundation

extension OwnID.CoreSDK {
    enum SDKAction {
        case configureFromDefaultConfiguration(userFacingSDK: OwnID.CoreSDK.SDKInformation,
                                               underlyingSDKs: [OwnID.CoreSDK.SDKInformation],
                                               supportedLanguages: OwnID.CoreSDK.Languages)
        case configureFrom(plistUrl: URL,
                           userFacingSDK: OwnID.CoreSDK.SDKInformation,
                           underlyingSDKs: [OwnID.CoreSDK.SDKInformation],
                           supportedLanguages: OwnID.CoreSDK.Languages)
        case configure(appID: OwnID.CoreSDK.AppID,
                       redirectionURL: OwnID.CoreSDK.RedirectionURLString?,
                       userFacingSDK: OwnID.CoreSDK.SDKInformation,
                       underlyingSDKs: [OwnID.CoreSDK.SDKInformation],
                       isTestingEnvironment: Bool,
                       environment: String?,
                       region: String?,
                       enableLogging: Bool?,
                       supportedLanguages: OwnID.CoreSDK.Languages)
        case configurationCreated(configuration: OwnID.CoreSDK.LocalConfiguration,
                                  userFacingSDK: OwnID.CoreSDK.SDKInformation,
                                  underlyingSDKs: [OwnID.CoreSDK.SDKInformation],
                                  isTestingEnvironment: Bool)
        case updateSupportedLanguages(supportedLanguages: OwnID.CoreSDK.Languages)
        case configureForTests
        case fetchServerConfiguration
        case save(configurationLoadingEvent: OwnID.CoreSDK.ConfigurationLoadingEvent, userFacingSDK: OwnID.CoreSDK.SDKInformation?)
        case fetchLogo(config: LocalConfiguration)
        case success
    }
}
