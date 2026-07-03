import Foundation

/// Parameters for email verification string resolution.
///
/// Email verification strings do not require per-call inputs.
public struct EmailVerificationStringsParams: StringsParams {
    /// Creates email verification string parameters.
    public init() {}
}

/// Complete UI strings for email verification.
///
/// - ``title``: Title text for the email verification view.
/// - ``message``: Instructional message for the email verification view. May include `%CODE_LENGTH%` and `%LOGIN_ID%`.
/// - ``description``: Description text for the verification step.
/// - ``resend``: Label for the resend-code action.
/// - ``cancel``: Label for the cancel action.
/// - ``notYou``: Label for the "not you?" link.
public struct EmailVerificationStrings: StringsData, Equatable {
    /// Embedded English fallback strings used when server locale data is unavailable or incomplete.
    public static var `default`: EmailVerificationStrings {
        EmailVerificationStrings(
            title: "Verify Your Email",
            message: "An email with a %CODE_LENGTH%-digit code was just sent to\n%LOGIN_ID%",
            description: "Enter the code",
            resend: "Resend email",
            cancel: "Cancel",
            notYou: "Not you?"
        )
    }

    /// Title text for the email verification view.
    public let title: String
    /// Instructional message for the email verification view. May include `%CODE_LENGTH%` and `%LOGIN_ID%`.
    public let message: String
    /// Description text for the verification step.
    public let description: String
    /// Label for the resend-code action.
    public let resend: String
    /// Label for the cancel action.
    public let cancel: String
    /// Label for the "not you?" link.
    public let notYou: String

    /// Creates email verification strings.
    ///
    /// - Parameters:
    ///   - title: Title text for the email verification view.
    ///   - message: Instructional message for the email verification view. May include `%CODE_LENGTH%` and `%LOGIN_ID%`.
    ///   - description: Description text for the verification step.
    ///   - resend: Label for the resend-code action.
    ///   - cancel: Label for the cancel action.
    ///   - notYou: Label for the "not you?" link.
    public init(title: String, message: String, description: String, resend: String, cancel: String, notYou: String) {
        self.title = title
        self.message = message
        self.description = description
        self.resend = resend
        self.cancel = cancel
        self.notYou = notYou
    }
}

/// Provides resolved strings for email verification.
///
/// Default SDK providers read email verification keys from server locale data and use
/// ``EmailVerificationStrings/default`` for any missing key.
public protocol EmailVerificationStringsProvider: StringsProvider, Sendable
where D == EmailVerificationStrings, P == EmailVerificationStringsParams {}

/// Repository that supplies complete email verification strings by applying embedded defaults.
public protocol EmailVerificationStringsEmbeddedRepository: EmbeddedRepository where D == EmailVerificationStrings {}

/// Repository that reads raw email verification string keys from server locale data.
public protocol EmailVerificationStringsServerRepository: ServerRepository {}

internal final class EmailVerificationStringsProviderImpl: EmailVerificationStringsProvider {
    private let underlyingProvider: AnyStringsProvider<EmailVerificationStrings, EmailVerificationStringsParams>

    init(
        languageTagsProvider: any LanguageTagsProvider,
        embeddedRepository: any EmailVerificationStringsEmbeddedRepository,
        serverRepository: any EmailVerificationStringsServerRepository,
        taskScope: TaskScope
    ) {
        let provider = StringsProviderImpl<EmailVerificationStrings, EmailVerificationStringsParams>(
            languageTagsProvider: languageTagsProvider,
            serverRepository: serverRepository,
            taskScope: taskScope,
            finalMapper: { params, serverStrings in
                return embeddedRepository.fallbackToEmbedded(params: params, map: serverStrings)
            }
        )

        self.underlyingProvider = AnyStringsProvider(provider)
    }

    func getStrings(params: EmailVerificationStringsParams) -> AsyncStream<EmailVerificationStrings?> {
        return underlyingProvider.getStrings(params: params)
    }
}
