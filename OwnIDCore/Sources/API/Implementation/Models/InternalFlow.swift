import Foundation

internal struct InternalFlow: Sendable, Codable, Hashable {
    /// Unique identifier for the flow
    internal private(set) var id: String
    internal private(set) var name: String?
    internal private(set) var source: InternalFlowSource
    internal private(set) var status: InternalFlowStatus
    /// UTC timestamp
    internal private(set) var startedAt: String
    /// UTC timestamp
    internal private(set) var completedAt: String?
    internal private(set) var errors: [InternalClientError]?
    internal private(set) var switchedToFlow: String?
    internal private(set) var insights: InternalFlowInsights?
    internal private(set) var steps: [InternalStep]

    internal init(
        id: String,
        name: String? = nil,
        source: InternalFlowSource,
        status: InternalFlowStatus,
        startedAt: String,
        completedAt: String? = nil,
        errors: [InternalClientError]? = nil,
        switchedToFlow: String? = nil,
        insights: InternalFlowInsights? = nil,
        steps: [InternalStep]
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.errors = errors
        self.switchedToFlow = switchedToFlow
        self.insights = insights
        self.steps = steps
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case id = "id"
        case name = "name"
        case source = "source"
        case status = "status"
        case startedAt = "startedAt"
        case completedAt = "completedAt"
        case errors = "errors"
        case switchedToFlow = "switchedToFlow"
        case insights = "insights"
        case steps = "steps"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(source, forKey: .source)
        try container.encode(status, forKey: .status)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encodeIfPresent(errors, forKey: .errors)
        try container.encodeIfPresent(switchedToFlow, forKey: .switchedToFlow)
        try container.encodeIfPresent(insights, forKey: .insights)
        try container.encode(steps, forKey: .steps)
    }
}
