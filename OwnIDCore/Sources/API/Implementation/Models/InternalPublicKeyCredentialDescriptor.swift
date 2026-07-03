import Foundation

internal struct InternalPublicKeyCredentialDescriptor: Sendable, Codable, Hashable {
    internal private(set) var type: InternalCredentialType
    /// Base64url encoded credential ID
    internal private(set) var id: String
    internal private(set) var transports: [InternalTransportType]?

    internal init(type: InternalCredentialType, id: String, transports: [InternalTransportType]? = nil) {
        self.type = type
        self.id = id
        self.transports = transports
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case type = "type"
        case id = "id"
        case transports = "transports"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(transports, forKey: .transports)
    }
}
