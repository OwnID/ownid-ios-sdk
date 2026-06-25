import Foundation

internal struct InternalLoginRequest: Sendable, Codable, Hashable {
    /// Optional login ID to authenticate.
    internal private(set) var loginId: InternalLoginId?
    /// Optional extended client capability hints.
    internal private(set) var extendedClientCapabilities: InternalLoginRequestExtendedClientCapabilities?

    internal init(
        loginId: InternalLoginId? = nil,
        extendedClientCapabilities: InternalLoginRequestExtendedClientCapabilities? = nil
    ) {
        self.loginId = loginId
        self.extendedClientCapabilities = extendedClientCapabilities
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case loginId = "loginId"
        case extendedClientCapabilities = "extendedClientCapabilities"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(loginId, forKey: .loginId)
        try container.encodeIfPresent(extendedClientCapabilities, forKey: .extendedClientCapabilities)
    }
}
