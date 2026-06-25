import Foundation

internal struct InternalAttestationOptionsRequest: Sendable, Codable, Hashable {
    internal private(set) var loginId: InternalLoginId?
    /// Display name for the user account
    internal private(set) var accountDisplayName: String?

    internal init(loginId: InternalLoginId? = nil, accountDisplayName: String? = nil) {
        self.loginId = loginId
        self.accountDisplayName = accountDisplayName
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case loginId = "loginId"
        case accountDisplayName = "accountDisplayName"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(loginId, forKey: .loginId)
        try container.encodeIfPresent(accountDisplayName, forKey: .accountDisplayName)
    }
}
