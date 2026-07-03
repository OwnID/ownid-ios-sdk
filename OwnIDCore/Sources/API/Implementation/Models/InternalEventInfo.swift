import Foundation

internal struct InternalEventInfo: Sendable, Codable, Hashable {
    /// Event category.
    internal private(set) var type: InternalEventInfoType
    /// Flows included in the event payload.
    internal private(set) var flows: [InternalFlow]

    internal init(type: InternalEventInfoType, flows: [InternalFlow]) {
        self.type = type
        self.flows = flows
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case type = "type"
        case flows = "flows"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(flows, forKey: .flows)
    }
}
