import Foundation

internal struct InternalStartVerificationResponse: Sendable, Codable, Hashable {
    /// The challenge's identifier
    internal private(set) var challengeId: InternalChallengeId
    internal private(set) var resendPolicy: InternalResendPolicy
    /// A numerical hint, in milliseconds, which indicates the time the calling web app is willing to wait for the creation operation to complete. This hint may be overridden by the browser.
    internal private(set) var timeout: InternalTimeout
    internal private(set) var attempts: Int
    /// The channel through which the challenge can be completed.
    internal private(set) var channel: InternalOperationChannel
    internal private(set) var methods: InternalChallengeResponseMethods

    internal init(
        challengeId: InternalChallengeId,
        resendPolicy: InternalResendPolicy,
        timeout: InternalTimeout,
        attempts: Int,
        channel: InternalOperationChannel,
        methods: InternalChallengeResponseMethods
    ) {
        self.challengeId = challengeId
        self.resendPolicy = resendPolicy
        self.timeout = timeout
        self.attempts = attempts
        self.channel = channel
        self.methods = methods
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case challengeId = "challengeId"
        case resendPolicy = "resendPolicy"
        case timeout = "timeout"
        case attempts = "attempts"
        case channel = "channel"
        case methods = "methods"
    }

    internal init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.challengeId = try container.decode(InternalChallengeId.self, forKey: .challengeId)
        self.resendPolicy = try container.decode(InternalResendPolicy.self, forKey: .resendPolicy)
        self.timeout = try container.decode(InternalTimeout.self, forKey: .timeout)
        let attempts = try container.decode(Int.self, forKey: .attempts)
        guard attempts >= 1 else {
            throw DecodingError.dataCorruptedError(
                forKey: .attempts,
                in: container,
                debugDescription: "Verification attempts must be at least 1."
            )
        }
        self.attempts = attempts
        self.channel = try container.decode(InternalOperationChannel.self, forKey: .channel)
        self.methods = try container.decode(InternalChallengeResponseMethods.self, forKey: .methods)
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(challengeId, forKey: .challengeId)
        try container.encode(resendPolicy, forKey: .resendPolicy)
        try container.encode(timeout, forKey: .timeout)
        try container.encode(attempts, forKey: .attempts)
        try container.encode(channel, forKey: .channel)
        try container.encode(methods, forKey: .methods)
    }
}
