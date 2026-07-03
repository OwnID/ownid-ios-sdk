import Foundation

internal struct InternalAccessTokenWithUserInfoResponse: Sendable, Codable, Hashable {
    /// A signed JWT that can be verified as a proof of successful operations
    internal private(set) var accessToken: String
    internal private(set) var loginId: InternalLoginId
    /// The user information
    internal private(set) var userInfo: [String: String]
    internal private(set) var provider: InternalOidcProvider

    internal init(accessToken: String, loginId: InternalLoginId, userInfo: [String: String], provider: InternalOidcProvider) {
        self.accessToken = accessToken
        self.loginId = loginId
        self.userInfo = userInfo
        self.provider = provider
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case accessToken = "accessToken"
        case loginId = "loginId"
        case userInfo = "userInfo"
        case provider = "provider"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accessToken, forKey: .accessToken)
        try container.encode(loginId, forKey: .loginId)
        try container.encode(userInfo, forKey: .userInfo)
        try container.encode(provider, forKey: .provider)
    }
}
