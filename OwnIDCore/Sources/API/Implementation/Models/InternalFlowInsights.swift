import Foundation

internal struct InternalFlowInsights: Sendable, Codable, Hashable {
    /// Duration in milliseconds
    internal private(set) var duration: Int64?
    /// Percentage of errors encountered in the flow
    internal private(set) var errorRate: Double?
    internal private(set) var retries: Int?
    internal private(set) var clicksCount: Int?
    /// Authentication method used in the flow
    internal private(set) var authMethod: InternalAuthMethod?
    /// Indicates if the user was logged in
    internal private(set) var loggedIn: Bool?
    /// Indicates if the user was registered
    internal private(set) var registered: Bool?

    internal init(
        duration: Int64? = nil,
        errorRate: Double? = nil,
        retries: Int? = nil,
        clicksCount: Int? = nil,
        authMethod: InternalAuthMethod? = nil,
        loggedIn: Bool? = nil,
        registered: Bool? = nil
    ) {
        self.duration = duration
        self.errorRate = errorRate
        self.retries = retries
        self.clicksCount = clicksCount
        self.authMethod = authMethod
        self.loggedIn = loggedIn
        self.registered = registered
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case duration = "duration"
        case errorRate = "errorRate"
        case retries = "retries"
        case clicksCount = "clicksCount"
        case authMethod = "authMethod"
        case loggedIn = "loggedIn"
        case registered = "registered"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encodeIfPresent(errorRate, forKey: .errorRate)
        try container.encodeIfPresent(retries, forKey: .retries)
        try container.encodeIfPresent(clicksCount, forKey: .clicksCount)
        try container.encodeIfPresent(authMethod, forKey: .authMethod)
        try container.encodeIfPresent(loggedIn, forKey: .loggedIn)
        try container.encodeIfPresent(registered, forKey: .registered)
    }
}
