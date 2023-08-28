import SwiftUI
import FirebaseCore
import FirebaseAuth
import OwnIDFirebaseSDK

@main
struct FirebaseDemoApp: App {
    init() {
        FirebaseApp.configure()
        OwnID.FirebaseSDK.configure()
        
        DispatchQueue.main.async {
            try? Auth.auth().signOut()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            LoginAndRegisterView()
        }
    }
}
