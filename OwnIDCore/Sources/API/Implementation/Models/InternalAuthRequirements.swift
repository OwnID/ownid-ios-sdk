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

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(targetScore, forKey: .targetScore)
        try container.encode(operations, forKey: .operations)
    }
}
