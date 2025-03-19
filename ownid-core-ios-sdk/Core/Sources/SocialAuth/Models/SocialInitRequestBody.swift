import Foundation

extension OwnID.CoreSDK.SocialAuthManager {
    struct InitRequestBody: Codable, Hashable {
        enum OauthResponseType: String, Codable, CaseIterable {
            case code = "code"
            case idToken = "id_token"
        }
        var loginIdHint: String?
        var oauthResponseType: OauthResponseType
        var redirectUri: String?
        
        init(loginIdHint: String? = nil, oauthResponseType: OauthResponseType, redirectUri: String? = nil) {
            self.loginIdHint = loginIdHint
            self.oauthResponseType = oauthResponseType
            self.redirectUri = redirectUri
        }
        
        enum CodingKeys: String, CodingKey, CaseIterable {
            case loginIdHint
            case oauthResponseType
            case redirectUri
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(loginIdHint, forKey: .loginIdHint)
            try container.encode(oauthResponseType, forKey: .oauthResponseType)
            try container.encodeIfPresent(redirectUri, forKey: .redirectUri)
        }
    }
}

