import Foundation

/// Login ID type configuration entry from the auth config.
internal struct InternalAppAuthConfigLoginIdConfigItem: Sendable, Codable, Hashable {
    /// Configured login ID type.
    internal private(set) var type: InternalLoginIdType
    /// Optional validation regex override for this login ID type.
    internal private(set) var regex: String?

    internal init(type: InternalLoginIdType, regex: String? = nil) {
        self.type = type
        self.regex = regex
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case type = "type"
        case regex = "regex"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(regex, forKey: .regex)
    }
}
