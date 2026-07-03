import Foundation

internal struct InternalOperationRequirement: Sendable, Codable, Hashable {
    /// Operation type to perform.
    internal private(set) var type: InternalOperationType
    /// Discrete score for an operation
    internal private(set) var score: Int
    /// List of available channels with ids to perform the operation
    internal private(set) var channels: [InternalOperationChannel]?

    internal init(type: InternalOperationType, score: Int, channels: [InternalOperationChannel]? = nil) {
        self.type = type
        self.score = score
        self.channels = channels
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case type = "type"
        case score = "score"
        case channels = "channels"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(score, forKey: .score)
        try container.encodeIfPresent(channels, forKey: .channels)
    }
}
