import Foundation

internal enum InternalErrorCode: String, Sendable, Codable, Hashable, CaseIterable {
    case aborted = "aborted"
    case cancelNotSupported = "cancel_not_supported"
    case deviceNotSupported = "device_not_supported"
    case domElementNotFound = "dom_element_not_found"
    case emptyLoginId = "empty_login_id"
    case forbidden = "forbidden"
    case integrationError = "integration_error"
    case invalidArgument = "invalid_argument"
    case invalidChallenge = "invalid_challenge"
    case loginIDTypeNotSupported = "login_id_type_not_supported"
    case loginIdValidationFailed = "login_id_validation_failed"
    case loginWithPasswordFailed = "login_with_password_failed"
    case maximumAttemptsReached = "maximum_attempts_reached"
    case maximumChallengesReached = "maximum_challenges_reached"
    case maximumResendAttemptsReached = "maximum_resend_attempts_reached"
    case missingCapabilityProvider = "missing_capability_provider"
    case missingChannel = "missing_channel"
    case network = "network"
    case noApplicablePasskeys = "no_applicable_passkeys"
    case notificationBlocked = "notification_blocked"
    case oidcFailed = "oidc_failed"
    case passkeyAlreadyRegistered = "passkey_already_registered"
    case passkeyNotCreated = "passkey_not_created"
    case passkeysNotSupported = "passkeys_not_supported"
    case screensNotReady = "screens_not_ready"
    case sessionNotEstablished = "session_not_established"
    case timeout = "timeout"
    case unauthorized = "unauthorized"
    case unknown = "unknown"
    case userBlocked = "user_blocked"
    case userChanged = "user_changed"
    case userNotFound = "user_not_found"
    case verificationCodeWrong = "verification_code_wrong"
    case widgetAlreadyExists = "widget_already_exists"

    internal init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = InternalErrorCode(rawValue: rawValue) ?? .unknown
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
