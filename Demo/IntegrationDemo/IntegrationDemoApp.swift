import SwiftUI
import OwnIDCoreSDK

extension IntegrationDemoApp {
    static let clientName = "Integration"
    static let version = "3.5.0"
}

@main
struct IntegrationDemoApp: App {
    @StateObject private var coordinator: AppCoordinator = AppCoordinator()
    
    init() {
        OwnID.CoreSDK.configure(userFacingSDK: IntegrationDemoApp.info())
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
