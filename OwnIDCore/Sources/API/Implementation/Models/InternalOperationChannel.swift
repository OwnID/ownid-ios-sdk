import Foundation

internal struct InternalOperationChannel: Sendable, Codable, Hashable {
    /// The channel through which the operation can be performed. The channel will be masked if it was not provided as operation input.
    internal private(set) var channel: String
    internal private(set) var id: String

    internal init(channel: String, id: String) {
        self.channel = channel
        self.id = id
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case channel = "channel"
        case id = "id"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(channel, forKey: .channel)
        try container.encode(id, forKey: .id)
    }
}
