import Foundation
import Combine

extension OwnID.CoreSDK.EnrollManager {
    struct State {
        let supportedLanguages: OwnID.CoreSDK.Languages
        
        var loginIdPublisher: AnyPublisher<String, Never>!
        var authTokenPublisher: AnyPublisher<String, Never>!
        var displayNamePublisher: AnyPublisher<String, Never>!
        
        var force = false
        
        var loginId: String!
        var authToken: String!
        var displayName: String!
        var session: OwnID.CoreSDK.SessionService!
        
        var enrollViewStore: Store<OwnID.UISDK.Enroll.ViewState, OwnID.UISDK.Enroll.Action>!
        
        var authManagerStore: Store<OwnID.CoreSDK.AuthManager.State, OwnID.CoreSDK.AuthManager.Action>!
        var authManager: OwnID.CoreSDK.AuthManager?
        
        let sourceMetricName = "Device Enrollment Modal"
        
        var initURL: URL {
            if #available(iOS 16.0, *) {
                return OwnID.CoreSDK.shared.serverURL!.appending(path: "/ownid/attestation/options")
            } else {
                return OwnID.CoreSDK.shared.serverURL!.appendingPathComponent("/ownid/attestation/options")
            }
        }
        
        var resultURL: URL {
            if #available(iOS 16.0, *) {
                return OwnID.CoreSDK.shared.serverURL!.appending(path: "/ownid/attestation/result")
            } else {
                return OwnID.CoreSDK.shared.serverURL!.appendingPathComponent("/ownid/attestation/result")
            }
        }
    }
}
