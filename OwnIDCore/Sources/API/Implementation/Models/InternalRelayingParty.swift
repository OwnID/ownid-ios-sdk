import Foundation

internal struct InternalRelayingParty: Sendable, Codable, Hashable {
    /// Relying Party identifier (passkey's domain)
    internal private(set) var id: String
    internal private(set) var name: String

    internal init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case id = "id"
        case name = "name"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
    }
}
