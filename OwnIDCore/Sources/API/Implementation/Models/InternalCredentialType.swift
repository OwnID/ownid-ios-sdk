import Foundation

/// The type of credential, always 'public-key'
///
/// OpenAPI source: `CredentialType` schema.
internal enum InternalCredentialType: String, Sendable, Codable, Hashable, CaseIterable {
    case publicKey = "public-key"
}
