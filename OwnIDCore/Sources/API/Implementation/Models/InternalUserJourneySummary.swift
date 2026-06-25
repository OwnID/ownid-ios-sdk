import Foundation

internal struct InternalUserJourneySummary: Sendable, Codable, Hashable {
    /// Unique identifier of the journey
    internal private(set) var id: String
    /// Traceparent header for distributed tracing
    internal private(set) var traceparent: String
    internal private(set) var reporter: InternalReporter
    internal private(set) var eventInfo: InternalEventInfo
    internal private(set) var deviceInfo: InternalClientDeviceInfo
    internal private(set) var userInfo: [InternalUserInfo]

    internal init(
        id: String,
        traceparent: String,
        reporter: InternalReporter,
        eventInfo: InternalEventInfo,
        deviceInfo: InternalClientDeviceInfo,
        userInfo: [InternalUserInfo]
    ) {
        self.id = id
        self.traceparent = traceparent
        self.reporter = reporter
        self.eventInfo = eventInfo
        self.deviceInfo = deviceInfo
        self.userInfo = userInfo
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case id = "id"
        case traceparent = "traceparent"
        case reporter = "reporter"
        case eventInfo = "eventInfo"
        case deviceInfo = "deviceInfo"
        case userInfo = "userInfo"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(traceparent, forKey: .traceparent)
        try container.encode(reporter, forKey: .reporter)
        try container.encode(eventInfo, forKey: .eventInfo)
        try container.encode(deviceInfo, forKey: .deviceInfo)
        try container.encode(userInfo, forKey: .userInfo)
    }
}
