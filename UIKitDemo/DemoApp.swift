import UIKit
import OwnIDGigyaSDK
import DemoComponents

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    let appConfig = AppConfiguration<GigyaServerConfig>()
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        GigyaShared.instance.initFor(apiKey: appConfig.config.apiKey,
                                     apiDomain: appConfig.config.apiDomain)
        OwnID.GigyaSDK.configure()
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}

