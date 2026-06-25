import Foundation

/// Identifies an OwnID challenge.
///
/// The value is encoded and decoded as a single string. The wrapper does not validate, trim, or redact the identifier;
/// callers that accept external input remain responsible for rejecting blank values when they are not valid there.
public struct ChallengeID: Codable, Sendable, Hashable, CustomStringConvertible {
    public let value: String

    public init(_ value: String) {
        self.value = value
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.value = try container.decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }

    public var description: String { value }
}
