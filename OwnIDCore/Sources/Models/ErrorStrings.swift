import Foundation

/// User-facing error messages keyed by ``ErrorCode``.
///
/// A complete instance contains one display string for every public error code. SDK string providers create these values
/// by resolving server-backed strings for the active language and filling any missing entries with embedded defaults.
/// ``default`` is the built-in English set used when localized strings are unavailable.
///
/// Use ``getString(for:)`` after the app has chosen an ``ErrorCode`` for display. Do not infer failure semantics from the
/// returned text; typed API, operation, and flow failures remain the source of truth for handling decisions.
public struct ErrorStrings: StringsData {
    public let aborted: String
    public let cancelNotSupported: String
    public let deviceNotSupported: String
    public let domElementNotFound: String
    public let emptyLoginID: String
    public let forbidden: String
    public let integrationError: String
    public let invalidArgument: String
    public let invalidChallenge: String
    public let loginIDTypeNotSupported: String
    public let loginIDValidationFailed: String
    public let loginWithPasswordFailed: String
    public let maximumAttemptsReached: String
    public let maximumChallengesReached: String
    public let maximumResendAttemptsReached: String
    public let missingCapabilityProvider: String
    public let missingChannel: String
    public let network: String
    public let noApplicablePasskeys: String
    public let notificationBlocked: String
    public let oidcFailed: String
    public let passkeyAlreadyRegistered: String
    public let passkeyNotCreated: String
    public let passkeysNotSupported: String
    public let screensNotReady: String
    public let sessionNotEstablished: String
    public let timeout: String
    public let unauthorized: String
    public let unknown: String
    public let userBlocked: String
    public let userChanged: String
    public let userNotFound: String
    public let verificationCodeWrong: String
    public let widgetAlreadyExists: String

    /// Creates a complete set of fallback error strings.
    ///
    /// Use these strings as last-resort messages when SDK-provided strings are unavailable. Each parameter maps to the
    /// ``ErrorCode`` case with the matching name.
    public init(
        aborted: String,
        cancelNotSupported: String,
        deviceNotSupported: String,
        domElementNotFound: String,
        emptyLoginID: String,
        forbidden: String,
        integrationError: String,
        invalidArgument: String,
        invalidChallenge: String,
        loginIDTypeNotSupported: String,
        loginIDValidationFailed: String,
        loginWithPasswordFailed: String,
        maximumAttemptsReached: String,
        maximumChallengesReached: String,
        maximumResendAttemptsReached: String,
        missingCapabilityProvider: String,
        missingChannel: String,
        network: String,
        noApplicablePasskeys: String,
        notificationBlocked: String,
        oidcFailed: String,
        passkeyAlreadyRegistered: String,
        passkeyNotCreated: String,
        passkeysNotSupported: String,
        screensNotReady: String,
        sessionNotEstablished: String,
        timeout: String,
        unauthorized: String,
        unknown: String,
        userBlocked: String,
        userChanged: String,
        userNotFound: String,
        verificationCodeWrong: String,
        widgetAlreadyExists: String
    ) {
        self.aborted = aborted
        self.cancelNotSupported = cancelNotSupported
        self.deviceNotSupported = deviceNotSupported
        self.domElementNotFound = domElementNotFound
        self.emptyLoginID = emptyLoginID
        self.forbidden = forbidden
        self.integrationError = integrationError
        self.invalidArgument = invalidArgument
        self.invalidChallenge = invalidChallenge
        self.loginIDTypeNotSupported = loginIDTypeNotSupported
        self.loginIDValidationFailed = loginIDValidationFailed
        self.loginWithPasswordFailed = loginWithPasswordFailed
        self.maximumAttemptsReached = maximumAttemptsReached
        self.maximumChallengesReached = maximumChallengesReached
        self.maximumResendAttemptsReached = maximumResendAttemptsReached
        self.missingCapabilityProvider = missingCapabilityProvider
        self.missingChannel = missingChannel
        self.network = network
        self.noApplicablePasskeys = noApplicablePasskeys
        self.notificationBlocked = notificationBlocked
        self.oidcFailed = oidcFailed
        self.passkeyAlreadyRegistered = passkeyAlreadyRegistered
        self.passkeyNotCreated = passkeyNotCreated
        self.passkeysNotSupported = passkeysNotSupported
        self.screensNotReady = screensNotReady
        self.sessionNotEstablished = sessionNotEstablished
        self.timeout = timeout
        self.unauthorized = unauthorized
        self.unknown = unknown
        self.userBlocked = userBlocked
        self.userChanged = userChanged
        self.userNotFound = userNotFound
        self.verificationCodeWrong = verificationCodeWrong
        self.widgetAlreadyExists = widgetAlreadyExists
    }

    /// Built-in English fallback messages used when no localized error strings are provided.
    public static var `default`: ErrorStrings {
        ErrorStrings(
            aborted: "Aborted",
            cancelNotSupported: "Cancel not supported",
            deviceNotSupported: "Device not supported",
            domElementNotFound: "DOM Element not found",
            emptyLoginID: "Login ID validation failed",
            forbidden: "You don't have permission to perform this action",
            integrationError: "Integration error",
            invalidArgument: "Invalid argument",
            invalidChallenge: "Challenge does not exist or is expired",
            loginIDTypeNotSupported: "Login ID type not supported",
            loginIDValidationFailed: "Login ID validation failed",
            loginWithPasswordFailed: "Login with password failed",
            maximumAttemptsReached: "Maximum attempts reached",
            maximumChallengesReached: "Maximum challenges reached",
            maximumResendAttemptsReached: "Code resend limit reached",
            missingCapabilityProvider: "No provider for the required capability was found",
            missingChannel: "Missing communication channel",
            network: "Network error occurred. Please check your connection and try again",
            noApplicablePasskeys: "No applicable passkeys",
            notificationBlocked: "Notification was recently dismissed by the user",
            oidcFailed: "Social login did not complete successfully",
            passkeyAlreadyRegistered: "Passkey already registered",
            passkeyNotCreated: "Passkey not created",
            passkeysNotSupported: "Passkeys not supported",
            screensNotReady: "Screens not ready",
            sessionNotEstablished: "Session not established",
            timeout: "Timeout",
            unauthorized: "You are not authorized to perform this action",
            unknown: "Something went wrong. Try again later.",
            userBlocked: "Account is blocked",
            userChanged: "User changed",
            userNotFound: "You don't have an account",
            verificationCodeWrong: "Wrong code. Please try again.",
            widgetAlreadyExists: "Widget with the same ID already exists, please destroy it first"
        )
    }

    /// Returns the display message for `errorCode` from this already selected string set.
    ///
    /// This lookup does not apply the SDK instance localization fallback chain. Use
    /// ``ErrorCode/toLocalizedMessage(instanceName:fallbackErrorStrings:)`` when a lookup should first try the current
    /// strings for an OwnID instance and then fall back to a supplied ``ErrorStrings``.
    public func getString(for errorCode: ErrorCode) -> String {
        switch errorCode {
        case .aborted: return aborted
        case .cancelNotSupported: return cancelNotSupported
        case .deviceNotSupported: return deviceNotSupported
        case .domElementNotFound: return domElementNotFound
        case .emptyLoginID: return emptyLoginID
        case .forbidden: return forbidden
        case .integrationError: return integrationError
        case .invalidArgument: return invalidArgument
        case .invalidChallenge: return invalidChallenge
        case .loginIDTypeNotSupported: return loginIDTypeNotSupported
        case .loginIDValidationFailed: return loginIDValidationFailed
        case .loginWithPasswordFailed: return loginWithPasswordFailed
        case .maximumAttemptsReached: return maximumAttemptsReached
        case .maximumChallengesReached: return maximumChallengesReached
        case .maximumResendAttemptsReached: return maximumResendAttemptsReached
        case .missingCapabilityProvider: return missingCapabilityProvider
        case .missingChannel: return missingChannel
        case .network: return network
        case .noApplicablePasskeys: return noApplicablePasskeys
        case .notificationBlocked: return notificationBlocked
        case .oidcFailed: return oidcFailed
        case .passkeyAlreadyRegistered: return passkeyAlreadyRegistered
        case .passkeyNotCreated: return passkeyNotCreated
        case .passkeysNotSupported: return passkeysNotSupported
        case .screensNotReady: return screensNotReady
        case .sessionNotEstablished: return sessionNotEstablished
        case .timeout: return timeout
        case .unauthorized: return unauthorized
        case .unknown: return unknown
        case .userBlocked: return userBlocked
        case .userChanged: return userChanged
        case .userNotFound: return userNotFound
        case .verificationCodeWrong: return verificationCodeWrong
        case .widgetAlreadyExists: return widgetAlreadyExists
        }
    }
}
