import Foundation

/// Parameters for phone verification string resolution.
///
/// Phone verification strings do not require per-call inputs.
public struct PhoneVerificationStringsParams: StringsParams {
    /// Creates phone verification string parameters.
    public init() {}
}

/// Complete UI strings for phone verification.
///
/// - ``title``: Title text for the phone verification view.
/// - ``message``: Instructional message for the phone verification view. May include `%CODE_LENGTH%` and `%LOGIN_ID%`.
/// - ``description``: Description text for the verification step.
/// - ``resend``: Label for the resend-code action.
/// - ``cancel``: Label for the cancel action.
/// - ``notYou``: Label for the "not you?" link.
public struct PhoneVerificationStrings: StringsData {
    /// Embedded English fallback strings used when server locale data is unavailable or incomplete.
    public static var `default`: PhoneVerificationStrings {
        PhoneVerificationStrings(
            title: "Verify Your Phone Number",
            message: "We have sent you a %CODE_LENGTH%-digit code to\n%LOGIN_ID%",
            description: "Enter the code",
            resend: "Resend SMS",
            cancel: "Cancel",
            notYou: "Not you?"
        )
    }

    /// Title text for the phone verification view.
    public let title: String
    /// Instructional message for the phone verification view. May include `%CODE_LENGTH%` and `%LOGIN_ID%`.
    public let message: String
    /// Description text for the verification step.
    public let description: String
    /// Label for the resend-code action.
    public let resend: String
    /// Label for the cancel action.
    public let cancel: String
    /// Label for the "not you?" link.
    public let notYou: String

    /// Creates phone verification strings.
    ///
    /// - Parameters:
    ///   - title: Title text for the phone verification view.
    ///   - message: Instructional message for the phone verification view. May include `%CODE_LENGTH%` and `%LOGIN_ID%`.
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

/// Provides resolved strings for phone verification.
///
/// Default SDK providers read phone verification keys from server locale data and use
/// ``PhoneVerificationStrings/default`` for any missing key.
public protocol PhoneVerificationStringsProvider: StringsProvider, Sendable
where D == PhoneVerificationStrings, P == PhoneVerificationStringsParams {}

/// Repository that supplies complete phone verification strings by applying embedded defaults.
public protocol PhoneVerificationStringsEmbeddedRepository: EmbeddedRepository where D == PhoneVerificationStrings {}

/// Repository that reads raw phone verification string keys from server locale data.
public protocol PhoneVerificationStringsServerRepository: ServerRepository {}

internal final class PhoneVerificationStringsImpl: PhoneVerificationStringsProvider {
    private let underlyingProvider: AnyStringsProvider<PhoneVerificationStrings, PhoneVerificationStringsParams>

    init(
        languageTagsProvider: any LanguageTagsProvider,
        embeddedRepository: any PhoneVerificationStringsEmbeddedRepository,
        serverRepository: any PhoneVerificationStringsServerRepository,
        taskScope: TaskScope
    ) {
        let provider = StringsProviderImpl<PhoneVerificationStrings, PhoneVerificationStringsParams>(
            languageTagsProvider: languageTagsProvider,
            serverRepository: serverRepository,
            taskScope: taskScope,
            finalMapper: { params, serverStrings in
                return embeddedRepository.fallbackToEmbedded(params: params, map: serverStrings)
            }
        )
        self.underlyingProvider = AnyStringsProvider(provider)
    }

    func getStrings(params: PhoneVerificationStringsParams) -> AsyncStream<PhoneVerificationStrings?> {
        return underlyingProvider.getStrings(params: params)
    }
}
