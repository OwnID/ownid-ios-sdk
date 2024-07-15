public extension OwnID.CoreSDK {
    static let sdkName = "Core"
    static let version = "3.4.0"
    static let APIVersion = "1"
    
    static func info() -> OwnID.CoreSDK.SDKInformation { (sdkName, version) }
}

public extension OwnID.CoreSDK {
    var appID: String? {
        store.value.configuration?.appID
    }
    
    var environment: String? {
        store.value.configuration?.environment
    }
    
    var serverURL: ServerURL? {
        store.value.configuration?.serverURL
    }
    
    var metricsURL: ServerURL? {
        store.value.configuration?.metricsURL
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
