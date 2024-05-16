import SwiftUI
import Gigya
import OwnIDGigyaSDK

@main
struct GigyaDemoApp: App {
    @StateObject private var coordinator: AppCoordinator = AppCoordinator()
    
    init() {
        Gigya.sharedInstance().initFor(apiKey: "3_hOdIVleWrXNvjArcZRwHJLiGA4e6Jrcwq7RfH5nL7ZUHyI_77z43_IQrJYxLbiq_", apiDomain: "us1.gigya.com")
        OwnID.GigyaSDK.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            AppCoordinatorView()
                .environmentObject(coordinator)
                .onAppear {
                    if Gigya.sharedInstance().isLoggedIn() {
                        Gigya.sharedInstance().logout()
                    }
                }
        }
    }
}
