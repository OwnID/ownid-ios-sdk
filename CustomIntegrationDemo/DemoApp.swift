import SwiftUI
import OwnIDCoreSDK

extension DemoApp {
    static let clientName = "CustomIntegrationDemoApp"
    static let version = "1.0.0"
}

@main
struct DemoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    var body: some Scene {
        WindowGroup {
            LoginAndRegisterView()
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        OwnID.CoreSDK.shared.configure(userFacingSDK: DemoApp.info(), underlyingSDKs: [])
        
        return true
    }
    
    private static func info() -> OwnID.CoreSDK.SDKInformation {
        (clientName, version)
    }
}
