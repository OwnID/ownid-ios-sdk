import Foundation

internal struct InternalAttestationAuthenticatorResponse: Sendable, Codable, Hashable {
    /// Client data in JSON format
    internal private(set) var clientDataJSON: String
    /// Attestation object
    internal private(set) var attestationObject: String
    internal private(set) var transports: [InternalTransportType]

    internal init(clientDataJSON: String, attestationObject: String, transports: [InternalTransportType]) {
        self.clientDataJSON = clientDataJSON
        self.attestationObject = attestationObject
        self.transports = transports
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case clientDataJSON = "clientDataJSON"
        case attestationObject = "attestationObject"
        case transports = "transports"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(clientDataJSON, forKey: .clientDataJSON)
        try container.encode(attestationObject, forKey: .attestationObject)
        try container.encode(transports, forKey: .transports)
    }
}
