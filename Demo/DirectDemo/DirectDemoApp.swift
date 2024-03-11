import SwiftUI
import OwnIDCoreSDK

extension DirectDemoApp {
    static let clientName = "Direct"
    static let version = "3.1.0"
}

@main
struct DirectDemoApp: App {
    init() {
        OwnID.CoreSDK.shared.configure(userFacingSDK: DirectDemoApp.info(),
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
