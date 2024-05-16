import SwiftUI
import OwnIDCoreSDK

extension DirectDemoApp {
    static let clientName = "Direct"
    static let version = "3.3.0"
}

@main
struct DirectDemoApp: App {
    @StateObject private var coordinator: AppCoordinator = AppCoordinator()
    
    init() {
        OwnID.CoreSDK.configure(userFacingSDK: DirectDemoApp.info())
    }
    
    var body: some Scene {
        WindowGroup {
            AppCoordinatorView()
                .environmentObject(coordinator)
        }
    }
    
    private static func info() -> OwnID.CoreSDK.SDKInformation {
        (clientName, version)
    }
}
