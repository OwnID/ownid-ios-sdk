import Foundation

/// Extended client capability hints attached to a login request.
internal struct InternalLoginRequestExtendedClientCapabilities: Sendable, Codable, Hashable {
    /// Passkey capability hints.
    internal private(set) var passkeys: InternalLoginRequestExtendedClientCapabilitiesPasskeys?

    internal init(passkeys: InternalLoginRequestExtendedClientCapabilitiesPasskeys? = nil) {
        self.passkeys = passkeys
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case passkeys = "passkeys"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(passkeys, forKey: .passkeys)
    }
}
