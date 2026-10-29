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

    internal init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.allow = try container.decode(Bool.self, forKey: .allow)
        let attempts = try container.decode(Double.self, forKey: .attempts)
        guard attempts.isFinite, attempts >= 0, attempts <= 10 else {
            throw DecodingError.dataCorruptedError(
                forKey: .attempts,
                in: container,
                debugDescription: "Resend attempts must be an integer between 0 and 10."
            )
        }
        let integerAttempts = Int(attempts)
        guard attempts == Double(integerAttempts) else {
            throw DecodingError.dataCorruptedError(
                forKey: .attempts,
                in: container,
                debugDescription: "Resend attempts must be an integer between 0 and 10."
            )
        }
        self.attempts = integerAttempts
        self.debounce = try container.decode(Int.self, forKey: .debounce)
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(allow, forKey: .allow)
        try container.encode(attempts, forKey: .attempts)
        try container.encode(debounce, forKey: .debounce)
    }
}
