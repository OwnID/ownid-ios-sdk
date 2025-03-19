import Foundation

extension OwnID.CoreSDK.SocialAuthManager {
    struct CompleteResponse: Codable, Hashable {
        var accessToken: String
        var loginId: LoginId?
        var userInfo: [String: String]

        enum CodingKeys: String, CodingKey, CaseIterable {
            case accessToken
            case loginId
            case userInfo
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(accessToken, forKey: .accessToken)
            try container.encodeIfPresent(loginId, forKey: .loginId)
            try container.encode(userInfo, forKey: .userInfo)
        }
    }

    struct LoginId: Codable, Hashable {
        enum ModelType: String, Codable, CaseIterable {
            case internalUserId = "InternalUserId"
            case userName = "UserName"
            case email = "Email"
            case phoneNumber = "PhoneNumber"
            case fido2CredentialId = "Fido2CredentialId"
            case anonymous = "Anonymous"
        }
        var id: String
        var type: ModelType

        enum CodingKeys: String, CodingKey, CaseIterable {
            case id
            case type
        }
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(type, forKey: .type)
        }
    }
}
