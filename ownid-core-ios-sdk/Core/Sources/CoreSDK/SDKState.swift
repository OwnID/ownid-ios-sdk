import Foundation
import Combine

extension OwnID.CoreSDK {
    struct SDKState {
        var configuration: OwnID.CoreSDK.LocalConfiguration?
        let configurationLoadingEventPublisher: PassthroughSubject<ConfigurationLoadingEvent, Never>
        var supportedLanguages: OwnID.CoreSDK.Languages = .init(rawValue: ["en"])
        var configurationRequestData: ConfigurationRequestData?
        var apiEndpoint: APIEndpoint = .live
    }
}

extension OwnID.CoreSDK.SDKState {
    struct ConfigurationRequestData {
        let config: OwnID.CoreSDK.LocalConfiguration
        let userFacingSDK: OwnID.CoreSDK.SDKInformation
        var isLoading: Bool
    }
}
