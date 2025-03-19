import Foundation

extension OwnID.CoreSDK.SocialAuthManager {
    struct CompleteRequestBody: Codable, Hashable {
        var challengeId: String
        var idToken: String
        
        enum CodingKeys: String, CodingKey {
            case challengeId
            case idToken
        }
    }
}
