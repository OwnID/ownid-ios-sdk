import Foundation

extension OwnID.CoreSDK.SocialAuthManager {
    struct CancelRequestBody: Codable, Hashable {
        var challengeId: String
        
        init(challengeId: String) {
            self.challengeId = challengeId
        }
        
        enum CodingKeys: String, CodingKey {
            case challengeId
        }
    }
}
