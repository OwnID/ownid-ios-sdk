import Foundation

/// A numerical hint, in milliseconds, which indicates the time the calling web app is willing to wait for the creation operation to complete. This hint may be overridden by the browser.
///
/// OpenAPI source: `Timeout` schema.
internal struct InternalTimeout: Sendable, Codable, Hashable {
    internal let value: Int64

    internal init(_ value: Int64) {
        self.value = value
    }

    internal init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.value = try container.decode(Int64.self)
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
