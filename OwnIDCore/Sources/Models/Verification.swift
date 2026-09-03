import Foundation

/// Server-issued challenge for a verification operation (OTP or magic link).
///
/// Challenges returned by OwnID APIs are normalized while they are mapped into this model: ``timeout`` is zero or
/// greater, ``ResendPolicy/debounce`` is at least one second, and ``Methods/Otp/length`` is at least four digits. Direct
/// initialization or `Codable` decoding keeps the supplied values except for normalization performed by nested value
/// types such as ``Timeout``.
///
/// `Codable` uses the public `challengeId`, `resendPolicy`, `timeout`, `attempts`, `methods`, and `channel` keys.
/// `description` includes ``channel``; ``OperationChannel`` redacts its channel value.
public struct VerificationChallenge: Codable, Sendable, Equatable, CustomStringConvertible {
    private enum CodingKeys: String, Sendable, CodingKey {
        case challengeID = "challengeId"
        case resendPolicy
        case timeout
        case attempts
        case methods
        case channel
    }

    public let challengeID: ChallengeID
    public let resendPolicy: ResendPolicy
    public let timeout: Timeout
    public let attempts: Int
    public let methods: Methods
    public let channel: OperationChannel

    /// Policy controlling whether and how often the verification code can be resent.
    ///
    /// Values returned by OwnID APIs use a ``debounce`` of at least one second. Direct initialization and `Codable`
    /// decoding keep ``allow``, ``attempts``, and ``debounce`` as supplied.
    public struct ResendPolicy: Codable, Sendable, Equatable {
        /// Whether resend is currently allowed.
        public let allow: Bool

        /// Maximum number of resend attempts.
        public let attempts: Int

        /// Seconds to wait before another resend is allowed.
        public let debounce: Int

        public init(allow: Bool, attempts: Int, debounce: Int) {
            self.allow = allow
            self.attempts = attempts
            self.debounce = debounce
        }
    }

    /// Available verification methods for this challenge.
    ///
    /// Challenges returned by OwnID APIs include at least one non-`nil` method. Direct initialization and `Codable`
    /// decoding do not enforce that requirement.
    public struct Methods: Codable, Sendable, Equatable {
        public let otp: Otp?

        public let magicLink: MagicLink?

        /// Creates a method set. Both methods may be `nil`.
        public init(otp: Otp?, magicLink: MagicLink?) {
            self.otp = otp
            self.magicLink = magicLink
        }

        /// OTP method configuration with the expected code ``length``.
        ///
        /// Values returned by OwnID APIs use a ``length`` of at least four. Direct initialization and `Codable` decoding
        /// keep the supplied value.
        public struct Otp: Codable, Sendable, Equatable {
            public let length: Int

            public init(length: Int) {
                self.length = length
            }
        }

        /// Marks magic-link verification as available.
        public struct MagicLink: Codable, Sendable, Equatable {

            public init() {}
        }
    }

    /// Creates a verification challenge.
    ///
    /// - Parameters:
    ///   - challengeID: Unique challenge identifier.
    ///   - resendPolicy: Policy controlling whether and how often codes can be resent.
    ///   - timeout: Timeout for the challenge.
    ///   - attempts: Maximum number of verification attempts allowed.
    ///   - methods: Available verification methods for this challenge.
    ///   - channel: Channel through which the challenge can be completed.
    public init(
        challengeID: ChallengeID,
        resendPolicy: ResendPolicy,
        timeout: Timeout,
        attempts: Int,
        methods: Methods,
        channel: OperationChannel
    ) {
        self.challengeID = challengeID
        self.resendPolicy = resendPolicy
        self.timeout = timeout
        self.attempts = attempts
        self.methods = methods
        self.channel = channel
    }

    public var description: String {
        "VerificationChallenge(challengeId: \(challengeID), timeout: \(timeout), attempts: \(attempts), methods: \(String(describing: methods)), channel: \(String(describing: channel)))"
    }
}

/// The type of verification delivery method.
///
/// `rawValue` is the stable OwnID method string used in API payloads. `VerificationMethod(rawValue:)` returns `nil` for
/// unknown strings, and `Codable` decoding fails for unknown raw values.
public enum VerificationMethod: String, Sendable, Codable {
    case magicLink = "MagicLink"

    case otp = "Otp"
}
