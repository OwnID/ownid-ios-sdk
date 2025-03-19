import Foundation

extension OwnID.CoreSDK.SocialAuthManager {
    struct State {
        let type: OwnID.CoreSDK.SocialProviderType
        var provider: SocialProvider?
        var session: OwnID.CoreSDK.SessionService!
        var challengeID = ""
        
        let sourceMetricName = "Social Feature"
        
        func initURL(type: OwnID.CoreSDK.SocialProviderType) -> URL {
            let type = type.rawValue
            if #available(iOS 16.0, *) {
                return OwnID.CoreSDK.shared.serverURL!.appending(path: "/api/oidc/idp/start/\(type)")
            } else {
                return OwnID.CoreSDK.shared.serverURL!.appendingPathComponent("/api/oidc/idp/start/\(type)")
            }
        }
        
        var resultURL: URL {
            if #available(iOS 16.0, *) {
                return OwnID.CoreSDK.shared.serverURL!.appending(path: "/api/oidc/idp/complete")
            } else {
                return OwnID.CoreSDK.shared.serverURL!.appendingPathComponent("/api/oidc/idp/complete")
            }
        }
        
        var loginURL: URL {
            if #available(iOS 16.0, *) {
                return OwnID.CoreSDK.shared.serverURL!.appending(path: "/api/login")
            } else {
                return OwnID.CoreSDK.shared.serverURL!.appendingPathComponent("/api/login")
            }
        }
        
        var cancelURL: URL {
            if #available(iOS 16.0, *) {
                return OwnID.CoreSDK.shared.serverURL!.appending(path: "/api/oidc/idp/cancel")
            } else {
                return OwnID.CoreSDK.shared.serverURL!.appendingPathComponent("/api/oidc/idp/cancel")
            }
        }
    }
}
