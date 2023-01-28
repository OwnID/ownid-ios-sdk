import SwiftUI
import OwnIDCoreSDK

extension DemoApp {
    static let clientName = "CustomIntegrationDemoApp"
    static let version = "1.0.0"
}

@main
struct DemoApp: App {
    init() {
        OwnID.CoreSDK.shared.configure(userFacingSDK: Self.info(),
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
