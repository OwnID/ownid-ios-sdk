import SwiftUI
import OwnIDCoreSDK

extension IntegrationDemoApp {
    static let clientName = "CustomIntegrationDemoApp"
    static let version = "3.0.0"
}

@main
struct IntegrationDemoApp: App {
    init() {
        OwnID.CoreSDK.shared.configure(userFacingSDK: IntegrationDemoApp.info(),
                                       underlyingSDKs: [], 
                                       supportedLanguages: .init(rawValue: Locale.preferredLanguages))
    }
    
    var body: some Scene {
        WindowGroup {
            LoginAndRegisterView()
        }
    }
    
    private static func info() -> OwnID.CoreSDK.SDKInformation {
        (clientName, version)
    }
}
