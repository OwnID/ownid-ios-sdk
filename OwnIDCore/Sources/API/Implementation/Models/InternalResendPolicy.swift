import Foundation

internal struct InternalResendPolicy: Sendable, Codable, Hashable {
    /// Indicates whether resending is allowed.
    internal private(set) var allow: Bool
    /// The maximum number of resends allowed.
    internal private(set) var attempts: Int
    /// The delay in seconds before another resend can be made.
    internal private(set) var debounce: Int

    internal init(allow: Bool, attempts: Int, debounce: Int) {
        self.allow = allow
        self.attempts = attempts
        self.debounce = debounce
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case allow = "allow"
        case attempts = "attempts"
        case debounce = "debounce"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(allow, forKey: .allow)
        try container.encode(attempts, forKey: .attempts)
        try container.encode(debounce, forKey: .debounce)
    }
}
