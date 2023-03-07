import SwiftUI
import OwnIDAmplifySDK

@main
struct FirebaseDemoApp: App {
    init() {
        OwnID.AmplifySDK.configure(appID: "qjjq02w8p1o4l8", redirectionURL: "com.ownid.CognitoDemo://ownid", environment: "dev")
    }
    
    var body: some Scene {
        WindowGroup {
            LoginAndRegisterView()
        }
    }
}
