import Foundation

public extension OwnID.CoreSDK {
    static let sdkName = "Core"
    static let version = "3.9.0"
    static let APIVersion = "1"
    
    static func info() -> OwnID.CoreSDK.SDKInformation { (sdkName, version) }
}

public extension OwnID.CoreSDK {
    var appID: String? {
        store.value.configuration?.appID
    }
    
    var region: String {
        store.value.configuration?.region ?? ""
    }
    
    var environment: String? {
        store.value.configuration?.environment
    }
    
    var apiBaseURL: URL? {
        store.value.configuration?.apiBaseURL
    }
    
    var supportedLocales: [String]? {
        store.value.configuration?.supportedLocales
    }
}

extension OwnID.CoreSDK {
    enum ConfigurationLoadingEvent {
        case loaded(LocalConfiguration)
        case error(Error)
    }
}
