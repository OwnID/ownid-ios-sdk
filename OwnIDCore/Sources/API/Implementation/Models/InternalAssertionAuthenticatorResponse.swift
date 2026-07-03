import Foundation

internal struct InternalAssertionAuthenticatorResponse: Sendable, Codable, Hashable {
    /// Client data in JSON format
    internal private(set) var clientDataJSON: String
    /// Authenticator data used in the assertion signing process
    internal private(set) var authenticatorData: String
    /// Base64url encoded identifier for a user account, specified by the Relying Party as user.id during registration
    internal private(set) var userHandle: String?
    /// Signature for the server challenge, returned from the authenticator
    internal private(set) var signature: String

    internal init(clientDataJSON: String, authenticatorData: String, userHandle: String? = nil, signature: String) {
        self.clientDataJSON = clientDataJSON
        self.authenticatorData = authenticatorData
        self.userHandle = userHandle
        self.signature = signature
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case clientDataJSON = "clientDataJSON"
        case authenticatorData = "authenticatorData"
        case userHandle = "userHandle"
        case signature = "signature"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(clientDataJSON, forKey: .clientDataJSON)
        try container.encode(authenticatorData, forKey: .authenticatorData)
        try container.encodeIfPresent(userHandle, forKey: .userHandle)
        try container.encode(signature, forKey: .signature)
    }
}
