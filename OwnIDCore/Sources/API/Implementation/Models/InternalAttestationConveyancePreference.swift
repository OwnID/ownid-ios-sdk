import Foundation

/// Attestation conveyance during credential generation
///
/// OpenAPI source: `AttestationConveyancePreference` schema.
internal enum InternalAttestationConveyancePreference: String, Sendable, Codable, Hashable, CaseIterable {
    case none = "none"
    case direct = "direct"
    case indirect = "indirect"
    case enterprise = "enterprise"
}
