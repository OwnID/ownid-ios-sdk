import SwiftUI
import DemoComponents

@main
struct DemoApp: App {
    let appConfig = AppConfiguration<GigyaServerConfig>()

    init() {
        GigyaShared.instance.initFor(apiKey: appConfig.config.apiKey,
                                     apiDomain: appConfig.config.apiDomain)
    }
    
    @StateObject var coordinator = AppCoordinator()
    
    var body: some Scene {
        WindowGroup {
            AppCoordinatorView(coordinator: coordinator)
        }
    }
}
