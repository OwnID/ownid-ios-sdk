import Foundation

/// Timeout in milliseconds, normalized to zero or greater.
///
/// Negative initializer and decoded values are clamped to `0`. The value encodes as a single integer containing the
/// normalized millisecond count.
public struct Timeout: Codable, Sendable, Hashable, Comparable, CustomStringConvertible {
    public let milliseconds: Int64

    public init(milliseconds: Int64) {
        self.milliseconds = max(0, milliseconds)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(milliseconds: try container.decode(Int64.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(milliseconds)
    }

    public var description: String { String(milliseconds) }

    public static func < (lhs: Timeout, rhs: Timeout) -> Bool {
        lhs.milliseconds < rhs.milliseconds
    }
}
