import Foundation

/// The challenge's identifier
///
/// OpenAPI source: `ChallengeId` schema.
internal struct InternalChallengeId: Sendable, Codable, Hashable {
    internal let value: String

    internal init(_ value: String) {
        self.value = value
    }

    internal init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.value = try container.decode(String.self)
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
