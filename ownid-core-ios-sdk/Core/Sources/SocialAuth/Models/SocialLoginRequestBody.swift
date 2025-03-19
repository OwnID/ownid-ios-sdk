import Foundation

extension OwnID.CoreSDK.SocialAuthManager {
    struct LoginRequestBody: Codable, Hashable {
        var loginId: LoginId?
        
        init(loginId: LoginId? = nil) {
            self.loginId = loginId
        }
        
        internal func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(loginId, forKey: .loginId)
        }
    }
}
