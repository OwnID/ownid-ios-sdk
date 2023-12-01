import SwiftUI
import Gigya
import OwnIDGigyaSDK

@main
struct GigyaDemoApp: App {
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
        Gigya.sharedInstance().initFor(apiKey: "3_O4QE0Kk7QstG4VGDPED5omrr8mgbTuf_Gim8V_Y19YDP75m_msuGtNGQz89X0KWP", apiDomain: "us1.gigya.com")
        OwnID.GigyaSDK.configure()
        
        return true
    }
}
