import OwnIDCore
import SwiftUI

/// Supplies custom SwiftUI content for email verification.
///
/// Register an implementation on the OwnID SDK instance when you want all email-verification operation UI for that
/// instance to use app-provided content. For a local override, use ``View/withEmailVerificationContent(_:)``; that
/// override wins for the affected SwiftUI subtree.
///
/// Custom content owns rendering, user input collection, loading display, and error presentation. Invoke callbacks
/// from ``EmailVerificationUIState`` only for matching user actions: submit the entered code through
/// ``EmailVerificationUIState/onCodeEntered``, request a new code through ``EmailVerificationUIState/onResend``, and
/// leave cancel/"not you" settlement to ``EmailVerificationUIState/onCancel`` and
/// ``EmailVerificationUIState/onNotYou``. Avoid duplicate non-cancel actions while
/// ``EmailVerificationUIState/isBusy`` is `true`. The operation owns challenge completion, cancellation, timeout,
/// callback failures, and the terminal ``OperationResult``.
///
/// The built-in provider requests one-time initial OTP focus when allowed, normalizes accepted decimal digits to ASCII,
/// and submits the code through ``EmailVerificationUIState/onCodeEntered`` as soon as the required length is entered
/// while the operation is not busy. It owns the visible busy spinner, clears the OTP field when an error arrives, hides
/// resend until the challenge debounce allows it, disables "not you" while busy, and invokes the supplied resend,
/// cancel, and "not you" callbacks only from the matching user actions.
public protocol EmailVerificationUIProvider: Sendable {
    /// Builds the SwiftUI view for the email verification form.
    ///
    /// The SDK calls this method on the main actor whenever operation state, localized strings, theme, or focus
    /// readiness changes. Keep business effects behind callbacks from `uiState` so SwiftUI updates do not submit
    /// codes, resend challenges, or cancel the operation on their own.
    ///
    /// - Parameters:
    ///   - uiState: Current UI state with the verification challenge, selected delivery address, busy flag, error, and
    ///     action callbacks. Use `uiState.challenge.channel.channel` as the selected delivery address and
    ///     `uiState.challenge.methods.otp?.length` as the expected OTP length.
    ///   - uiStrings: Localized strings for the email verification UI. `message` may contain `%CODE_LENGTH%` and
    ///     `%LOGIN_ID%` placeholders for the visible code length and selected delivery address.
    ///   - errorTextProvider: Optional provider from SDK-reported ``ErrorCode`` values to display text. When it is
    ///     `nil`, use the current ``UIError/localizedMessage``.
    ///   - isReadyForInitialFocus: `true` when the surrounding presentation is ready for one-time initial text input
    ///     focus.
    /// - Returns: A view that renders the verification form for the current state.
    @MainActor func content(
        uiState: EmailVerificationUIState,
        uiStrings: EmailVerificationStrings,
        errorTextProvider: ((ErrorCode) -> String)?,
        isReadyForInitialFocus: Bool
    ) -> AnyView
}
