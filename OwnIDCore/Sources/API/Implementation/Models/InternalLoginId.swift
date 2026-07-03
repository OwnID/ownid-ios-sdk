import Foundation

internal struct InternalLoginId: Sendable, Codable, Hashable {
    /// Raw login identifier value.
    internal private(set) var id: String
    /// Classified login ID type.
    internal private(set) var type: InternalLoginIdType

    internal init(id: String, type: InternalLoginIdType) {
        self.id = id
        self.type = type
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case id = "id"
        case type = "type"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
    }
}
