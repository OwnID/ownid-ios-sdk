import Foundation

internal struct InternalStepInsights: Sendable, Codable, Hashable {
    /// Duration in milliseconds
    internal private(set) var duration: Int64?
    /// Number of retries recorded for the step.
    internal private(set) var retries: Int?
    /// Number of clicks recorded for the step.
    internal private(set) var clicksCount: Int?

    internal init(duration: Int64? = nil, retries: Int? = nil, clicksCount: Int? = nil) {
        self.duration = duration
        self.retries = retries
        self.clicksCount = clicksCount
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case duration = "duration"
        case retries = "retries"
        case clicksCount = "clicksCount"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encodeIfPresent(retries, forKey: .retries)
        try container.encodeIfPresent(clicksCount, forKey: .clicksCount)
    }
}
