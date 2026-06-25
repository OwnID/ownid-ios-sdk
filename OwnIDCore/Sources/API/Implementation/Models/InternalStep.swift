import Foundation

internal struct InternalStep: Sendable, Codable, Hashable {
    /// Operation type represented by this step.
    internal private(set) var operationType: InternalOperationType
    /// Optional step name.
    internal private(set) var name: String?
    /// Step status.
    internal private(set) var status: InternalStepStatus
    /// UTC timestamp
    internal private(set) var startedAt: String
    /// UTC timestamp
    internal private(set) var completedAt: String?
    /// Client-side errors captured for this step.
    internal private(set) var errors: [InternalClientError]?
    /// Step-level analytics metrics.
    internal private(set) var insights: InternalStepInsights?

    internal init(
        operationType: InternalOperationType,
        name: String? = nil,
        status: InternalStepStatus,
        startedAt: String,
        completedAt: String? = nil,
        errors: [InternalClientError]? = nil,
        insights: InternalStepInsights? = nil
    ) {
        self.operationType = operationType
        self.name = name
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.errors = errors
        self.insights = insights
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case operationType = "operationType"
        case name = "name"
        case status = "status"
        case startedAt = "startedAt"
        case completedAt = "completedAt"
        case errors = "errors"
        case insights = "insights"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(operationType, forKey: .operationType)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(status, forKey: .status)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encodeIfPresent(errors, forKey: .errors)
        try container.encodeIfPresent(insights, forKey: .insights)
    }
}
