import OwnIDCore
import SwiftUI

/// Supplies custom SwiftUI content for phone verification.
///
/// Register an implementation on the OwnID SDK instance when you want all phone-verification operation UI for that
/// instance to use app-provided content. For a local override, use ``View/withPhoneVerificationContent(_:)``.
/// A local override takes precedence for that app-hosted operation view.
///
/// App-provided content remains responsible only for rendering and user-event wiring; the operation continues to own
/// challenge completion, resend, cancel, timeout, and result settlement.
///
/// The built-in provider requests one-time initial OTP focus when allowed, normalizes accepted decimal digits to ASCII,
/// and submits the code through ``PhoneVerificationUIState/onCodeEntered`` as soon as the required length is entered
/// while the operation is not busy. It displays the operation busy state, maps errors through the supplied error text
/// provider when present, clears the OTP field when an error arrives, hides resend until the challenge debounce allows
/// it, disables "not you" while busy, and invokes the supplied resend, cancel, and "not you" callbacks only from the
/// matching user actions.
public protocol PhoneVerificationUIProvider: Sendable {
    /// Builds the SwiftUI view for the phone verification form.
    ///
    /// The SDK calls this method on the main actor only while the phone verification operation is active. After the
    /// operation succeeds, is canceled, or fails terminally, ``OwnIDOperationView`` stops rendering operation content
    /// and the caller should observe the terminal result from its operation controller.
    ///
    /// Custom content owns rendering, focus, loading indicators, error presentation, and user-event wiring. Use
    /// ``PhoneVerificationUIState/challenge`` for the expected OTP length, submit the OTP through
    /// ``PhoneVerificationUIState/onCodeEntered`` when the user enters that length, request another code through
    /// ``PhoneVerificationUIState/onResend`` only when the challenge resend policy allows it, and use
    /// ``PhoneVerificationUIState/onCancel`` or ``PhoneVerificationUIState/onNotYou`` for those user actions.
    /// Do not complete or cancel the operation from unrelated app state.
    ///
    /// - Parameters:
    ///   - uiState: Current UI state with the verification challenge, selected delivery phone number, busy flag, error,
    ///     and action callbacks. Use `uiState.challenge.channel.channel` as the selected delivery phone number and
    ///     `uiState.challenge.methods.otp?.length` as the expected OTP length.
    ///   - uiStrings: Localized strings for the phone verification UI. `message` may contain `%CODE_LENGTH%` and
    ///     `%LOGIN_ID%` placeholders for the visible code length and selected delivery phone number.
    ///   - errorTextProvider: Optional provider from SDK-reported ``ErrorCode`` values to display text. When it is
    ///     `nil`, use the current ``UIError/localizedMessage``.
    ///   - isReadyForInitialFocus: `true` when the surrounding presentation is ready for one-time initial text input
    ///     focus.
    /// - Returns: A view that renders the verification form for the current state.
    @MainActor func content(
        uiState: PhoneVerificationUIState,
        uiStrings: PhoneVerificationStrings,
        errorTextProvider: ((ErrorCode) -> String)?,
        isReadyForInitialFocus: Bool
    ) -> AnyView
}
