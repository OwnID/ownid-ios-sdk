import Foundation

extension OwnID.CoreSDK.EnrollManager {
    struct AttestationOptions: Encodable {
        let displayName: String
        let username: String
        
        init(displayName: String, username: String) {
            self.displayName = displayName
            self.username = username
        }
    }
}
