import Foundation

/// Passkey-specific capability hints attached to a login request.
internal struct InternalLoginRequestExtendedClientCapabilitiesPasskeys: Sendable, Codable, Hashable {
    /// Whether the client supports passkey presence checks without starting a full flow.
    internal private(set) var peek: Bool?

    internal init(peek: Bool? = nil) {
        self.peek = peek
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case peek = "peek"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(peek, forKey: .peek)
    }
}
