import Foundation

internal struct InternalUserInfo: Sendable, Codable, Hashable {
    internal private(set) var loginId: InternalLoginId
    internal private(set) var returningUser: Bool?
    internal private(set) var lastAuthMethod: InternalAuthMethod?

    internal init(loginId: InternalLoginId, returningUser: Bool? = nil, lastAuthMethod: InternalAuthMethod? = nil) {
        self.loginId = loginId
        self.returningUser = returningUser
        self.lastAuthMethod = lastAuthMethod
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case loginId = "loginId"
        case returningUser = "returningUser"
        case lastAuthMethod = "lastAuthMethod"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(loginId, forKey: .loginId)
        try container.encodeIfPresent(returningUser, forKey: .returningUser)
        try container.encodeIfPresent(lastAuthMethod, forKey: .lastAuthMethod)
    }
}
