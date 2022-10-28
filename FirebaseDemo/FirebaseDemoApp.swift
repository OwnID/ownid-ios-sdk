import SwiftUI
import FirebaseCore
import FirebaseAuth
import OwnIDFirebaseSDK

@main
struct FirebaseDemoApp: App {
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
        FirebaseApp.configure()
        OwnID.FirebaseSDK.configure()
        
        DispatchQueue.main.async {
            try? Auth.auth().signOut()
        }
        
        return true
    }
}
