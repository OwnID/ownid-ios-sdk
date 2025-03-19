import Foundation

extension OwnID.CoreSDK.SocialAuthManager {
    struct InitResponse: Codable, Hashable {
        var challengeId: String
        var timeout: Int64
        var clientId: String
        var challengeUrl: String?
        
        enum CodingKeys: String, CodingKey, CaseIterable {
            case challengeId
            case timeout
            case clientId
            case challengeUrl
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(challengeId, forKey: .challengeId)
            try container.encode(timeout, forKey: .timeout)
            try container.encode(clientId, forKey: .clientId)
            try container.encodeIfPresent(challengeUrl, forKey: .challengeUrl)
        }
    }
}
