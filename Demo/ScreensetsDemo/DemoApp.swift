import SwiftUI
import Gigya
import OwnIDGigyaSDK

@main
struct DemoApp: App {
    
    init() {
        Gigya.sharedInstance().initFor(apiKey: "...", apiDomain: "...")
        OwnID.GigyaSDK.configure(appID: "...")
        OwnID.GigyaSDK.configureWebBridge()
    }
    
    var body: some Scene {
        WindowGroup {
            LogInView()
                .padding(EdgeInsets(top: 24, leading: 24, bottom: 24, trailing: 24))
                .background(Color.white)
                .padding()
                .onAppear {
                    if Gigya.sharedInstance().isLoggedIn() {
                        Gigya.sharedInstance().logout()
                    }
                }
        }
    }
}
