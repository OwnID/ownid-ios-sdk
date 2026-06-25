import Foundation

/// Parameters for login ID collection.
///
/// - Parameter loginIDTypes: Login ID types the form can collect. Email, phone number, and username select the
///   matching server keys and embedded defaults; duplicate values are ignored, and other values do not affect string
///   selection.
public struct LoginIDCollectStringsParams: StringsParams {
    /// Login ID types the form can collect.
    public let loginIDTypes: [LoginIDType]

    /// Creates login ID collection string parameters.
    ///
    /// - Parameter loginIDTypes: Login ID types the form can collect.
    public init(loginIDTypes: [LoginIDType]) {
        self.loginIDTypes = loginIDTypes
    }
}

/// Complete UI strings for login ID collection.
///
/// - ``title``: Title text for the login ID collection view.
/// - ``message``: Instructional message for the login ID collection view.
/// - ``placeholder``: Placeholder text for the login ID input field.
/// - ``cancel``: Label for the cancel action.
/// - ``cta``: Label for the primary action button.
/// - ``error``: Error message shown for ``ErrorCode/loginIDValidationFailed``.
public struct LoginIDCollectStrings: StringsData {
    /// Returns embedded English fallback strings for a login ID collection form.
    ///
    /// Email, phone number, and username values select the corresponding single or combined prompt. Unsupported values
    /// are ignored; if no supported type remains, all returned strings are empty. When the platform passkey
    /// authenticator is available, the title and message use biometric sign-in wording.
    public static func `default`(loginIDTypes: [LoginIDType], isSystemFidoCapable: Bool) -> LoginIDCollectStrings {
        let fidoTitle = "Sign In with Face ID"

        let loginIDTypes = Set(loginIDTypes.filter { $0 == .email || $0 == .phoneNumber || $0 == .userName })
        switch loginIDTypes {
        case [.email]:
            return LoginIDCollectStrings(
                title: isSystemFidoCapable ? fidoTitle : "Enter your email",
                message: isSystemFidoCapable ? "Enter your email" : "to receive a one-time code",
                placeholder: "Email",
                cancel: "Cancel",
                cta: "Continue",
                error: "Enter a valid email"
            )
        case [.phoneNumber]:
            return LoginIDCollectStrings(
                title: isSystemFidoCapable ? fidoTitle : "Enter your phone number",
                message: isSystemFidoCapable ? "Enter your phone number" : "to receive a one-time code",
                placeholder: "Phone number",
                cancel: "Cancel",
                cta: "Continue",
                error: "Enter a valid phone number"
            )
        case [.userName]:
            return LoginIDCollectStrings(
                title: isSystemFidoCapable ? fidoTitle : "Enter your ID number",
                message: isSystemFidoCapable ? "Enter your ID number" : "to receive a one-time code",
                placeholder: "ID number",
                cancel: "Cancel",
                cta: "Continue",
                error: "Enter a valid ID number"
            )

        case [.email, .phoneNumber]:
            return LoginIDCollectStrings(
                title: isSystemFidoCapable ? fidoTitle : "Enter your email or phone number",
                message: isSystemFidoCapable ? "Enter your email or phone number" : "to receive a one-time code",
                placeholder: "Email or phone number",
                cancel: "Cancel",
                cta: "Continue",
                error: "Enter a valid email or phone number"
            )

        case [.email, .userName]:
            return LoginIDCollectStrings(
                title: isSystemFidoCapable ? fidoTitle : "Enter your email or ID number",
                message: isSystemFidoCapable ? "Enter your email or ID number" : "to receive a one-time code",
                placeholder: "Email or ID number",
                cancel: "Cancel",
                cta: "Continue",
                error: "Enter a valid email or ID number"
            )

        case [.phoneNumber, .userName]:
            return LoginIDCollectStrings(
                title: isSystemFidoCapable ? fidoTitle : "Enter your phone or ID number",
                message: isSystemFidoCapable ? "Enter your phone or ID number" : "to receive a one-time code",
                placeholder: "Phone or ID number",
                cancel: "Cancel",
                cta: "Continue",
                error: "Enter a valid phone or ID number"
            )

        case [.email, .phoneNumber, .userName]:
            return LoginIDCollectStrings(
                title: isSystemFidoCapable ? fidoTitle : "Enter your email, phone or ID number",
                message: isSystemFidoCapable ? "Enter your email, phone or ID number" : "to receive a one-time code",
                placeholder: "Email, phone or ID number",
                cancel: "Cancel",
                cta: "Continue",
                error: "Enter a valid email, phone or ID number"
            )

        default:
            return LoginIDCollectStrings(title: "", message: "", placeholder: "", cancel: "", cta: "", error: "")
        }
    }

    /// Title text for the login ID collection view.
    public let title: String
    /// Instructional message for the login ID collection view.
    public let message: String
    /// Placeholder text for the login ID input field.
    public let placeholder: String
    /// Label for the cancel action.
    public let cancel: String
    /// Label for the primary action button.
    public let cta: String
    /// Error message shown for ``ErrorCode/loginIDValidationFailed``.
    public let error: String

    /// Creates login ID collection strings.
    ///
    /// - Parameters:
    ///   - title: Title text for the login ID collection view.
    ///   - message: Instructional message for the login ID collection view.
    ///   - placeholder: Placeholder text for the login ID input field.
    ///   - cancel: Label for the cancel action.
    ///   - cta: Label for the primary action button.
    ///   - error: Error message shown for ``ErrorCode/loginIDValidationFailed``.
    public init(title: String, message: String, placeholder: String, cancel: String, cta: String, error: String) {
        self.title = title
        self.message = message
        self.placeholder = placeholder
        self.cancel = cancel
        self.cta = cta
        self.error = error
    }
}

/// Provides resolved strings for login ID collection.
///
/// Default SDK providers select the server locale keys from ``LoginIDCollectStringsParams/loginIDTypes`` and platform
/// passkey availability, then use ``LoginIDCollectStrings/default(loginIDTypes:isSystemFidoCapable:)`` for any missing
/// key.
public protocol LoginIDCollectStringsProvider: StringsProvider, Sendable
where D == LoginIDCollectStrings, P == LoginIDCollectStringsParams {}

/// Repository that supplies complete login ID collection strings by applying embedded defaults.
public protocol LoginIDCollectStringsEmbeddedRepository: EmbeddedRepository where D == LoginIDCollectStrings {}

/// Repository that reads raw login ID collection string keys from server locale data.
public protocol LoginIDCollectStringsServerRepository: ServerRepository {}

internal final class LoginIDCollectStringsProviderImpl: LoginIDCollectStringsProvider {
    private let underlyingProvider: AnyStringsProvider<LoginIDCollectStrings, LoginIDCollectStringsParams>

    init(
        languageTagsProvider: any LanguageTagsProvider,
        embeddedRepository: any LoginIDCollectStringsEmbeddedRepository,
        serverRepository: any LoginIDCollectStringsServerRepository,
        taskScope: TaskScope
    ) {
        let provider = StringsProviderImpl<LoginIDCollectStrings, LoginIDCollectStringsParams>(
            languageTagsProvider: languageTagsProvider,
            serverRepository: serverRepository,
            taskScope: taskScope,
            finalMapper: { params, serverStrings in
                return embeddedRepository.fallbackToEmbedded(params: params, map: serverStrings)
            }
        )
        self.underlyingProvider = AnyStringsProvider(provider)
    }

    func getStrings(params: LoginIDCollectStringsParams) -> AsyncStream<LoginIDCollectStrings?> {
        return underlyingProvider.getStrings(params: params)
    }
}
