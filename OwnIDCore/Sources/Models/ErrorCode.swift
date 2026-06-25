import Foundation

/// Stable OwnID error key used for localization and cross-surface failure labels.
///
/// OwnID result and failure types carry this key so app UI can resolve consistent copy. Branch on typed API, operation,
/// or flow failures for semantic handling; use this value as the display-message key after the app has chosen to show an
/// OwnID error.
public enum ErrorCode: String, Sendable, Codable, Hashable, CaseIterable, CustomStringConvertible {
    case aborted = "aborted"

    case cancelNotSupported = "cancel_not_supported"

    case deviceNotSupported = "device_not_supported"

    case domElementNotFound = "dom_element_not_found"

    case emptyLoginID = "empty_login_id"

    case forbidden = "forbidden"

    case integrationError = "integration_error"

    case invalidArgument = "invalid_argument"

    case invalidChallenge = "invalid_challenge"

    case loginIDTypeNotSupported = "login_id_type_not_supported"

    case loginIDValidationFailed = "login_id_validation_failed"

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

    public var value: String { rawValue }

    public var description: String { rawValue }

    /// Returns the localized message for this error code.
    ///
    /// Use this after the app has decided that an OwnID error should be shown and that the SDK default copy fits the
    /// current screen. This function only translates the lookup key to text. It does not decide whether to show an error,
    /// whether a more generic message is safer, or what recovery action the UI should offer. Use typed operation, flow,
    /// or API failure values for semantic handling.
    ///
    /// The message is resolved from the current error strings for `instanceName`. Those strings follow the SDK
    /// localization fallback chain. If the instance is missing, has no resolver, or has not emitted strings yet,
    /// `fallbackErrorStrings` provides the message. `fallbackErrorStrings` is not a localization override. For custom
    /// app copy, use the code as a lookup key and provide your own message.
    ///
    /// - Parameters:
    ///   - instanceName: OwnID instance whose error strings should be used.
    ///   - fallbackErrorStrings: Last-resort strings used when the instance cannot provide current error strings.
    public func toLocalizedMessage(
        instanceName: InstanceName = .default,
        fallbackErrorStrings: ErrorStrings = .default
    ) -> String {
        OwnIDRootDIContainer.shared.getInstanceContainer(instanceName)?
            .getOrNil(type: ErrorStringsResolver.self)?
            .toLocalizedMessage(errorCode: self, fallbackErrorStrings: fallbackErrorStrings)
            ?? resolveLocalizedMessage(errorStrings: fallbackErrorStrings)
    }

    internal func resolveLocalizedMessage(errorStrings: ErrorStrings) -> String {
        errorStrings.getString(for: self)
    }
}
