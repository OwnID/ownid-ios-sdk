import SwiftUI
import Gigya
import OwnIDGigyaSDK

@main
struct GigyaDemoApp: App {
    @StateObject private var coordinator: AppCoordinator = AppCoordinator()
    
    init() {
        Gigya.sharedInstance().initFor(apiKey: "3_O4QE0Kk7QstG4VGDPED5omrr8mgbTuf_Gim8V_Y19YDP75m_msuGtNGQz89X0KWP", apiDomain: "us1.gigya.com")
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
