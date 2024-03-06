import SwiftUI
import OwnIDCoreSDK

extension IntegrationDemoApp {
    static let clientName = "Integration"
    static let version = "3.1.0"
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
