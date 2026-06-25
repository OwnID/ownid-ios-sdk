import Foundation

internal struct InternalFido2User: Sendable, Codable, Hashable {
    /// Base64url encoded user ID
    internal private(set) var id: String
    /// User's name
    internal private(set) var name: String
    /// User's display name
    internal private(set) var displayName: String

    internal init(id: String, name: String, displayName: String) {
        self.id = id
        self.name = name
        self.displayName = displayName
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case id = "id"
        case name = "name"
        case displayName = "displayName"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(displayName, forKey: .displayName)
    }
}
