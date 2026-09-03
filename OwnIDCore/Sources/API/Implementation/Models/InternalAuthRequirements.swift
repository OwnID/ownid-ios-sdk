import Foundation

internal struct InternalAuthRequirements: Sendable, Codable, Hashable {
    /// Discrete score for an operation
    internal private(set) var targetScore: Int
    /// Sorted list of recommended operations that can be performed to reach the target score
    internal private(set) var operations: [InternalOperationRequirement]

    internal init(targetScore: Int, operations: [InternalOperationRequirement]) {
        self.targetScore = targetScore
        self.operations = operations
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case targetScore = "targetScore"
        case operations = "operations"
    }

    internal init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.targetScore = try container.decode(Int.self, forKey: .targetScore)
        guard targetScore >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .targetScore,
                in: container,
                debugDescription: "Target score must be non-negative."
            )
        }
        self.operations = try container.decode([InternalOperationRequirement].self, forKey: .operations)
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(targetScore, forKey: .targetScore)
        try container.encode(operations, forKey: .operations)
    }
}
