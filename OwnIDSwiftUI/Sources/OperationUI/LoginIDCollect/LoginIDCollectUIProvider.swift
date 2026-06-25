import OwnIDCore
import SwiftUI

/// Supplies custom SwiftUI content for login ID collection.
///
/// Register an implementation on the OwnID SDK instance when you want all login-ID-collection operation UI for that
/// instance to use app-provided content. For a local override, use ``View/withLoginIDCollectContent(_:)``.
/// Local overrides take precedence for the ``OwnIDOperationView`` subtree that provides them; otherwise the registered
/// provider content is used.
///
/// The provider is responsible for returning content that can render the supplied state, display or otherwise surface
/// validation errors, and call the state callbacks for submit and cancel actions. The SDK remains responsible for
/// default parameter resolution, validation, timeout, abort handling, and operation settlement.
///
/// The built-in provider requests one-time initial focus when allowed, configures keyboard and autofill hints from
/// the collectable login ID types, updates the operation through ``LoginIDCollectUIState/onLoginIDChange``, and
/// submits through ``LoginIDCollectUIState/onContinue``. Login ID validation failures use the localized collection
/// error string; other errors use `errorTextProvider` when supplied and otherwise fall back to
/// ``UIError/localizedMessage``. The default form exposes a cancel action that invokes
/// ``LoginIDCollectUIState/onCancel``; it does not add a busy state, resend action, or "not you" action.
public protocol LoginIDCollectUIProvider: Sendable {
    /// Builds the SwiftUI view for the login ID collection form.
    ///
    /// The SDK calls this method on the main actor while the operation is active and after localized strings have been
    /// resolved. The operation owns the current input value, validation, error updates, cancellation, and final
    /// settlement; custom content owns only SwiftUI rendering and wiring user actions to the supplied
    /// ``LoginIDCollectUIState`` callbacks.
    ///
    /// - Parameters:
    ///   - uiState: Current UI state with the login ID value, validation error, and action callbacks.
    ///   - uiStrings: Localized strings for the login ID collection UI.
    ///   - errorTextProvider: Optional provider from SDK-reported ``ErrorCode`` values to display text. When it is
    ///     `nil`, use the current ``UIError/localizedMessage``.
    ///   - isReadyForInitialFocus: `true` when the surrounding presentation is ready for one-time initial text input
    ///     focus.
    /// - Returns: A view that renders the collection form for the current state.
    ///
    /// Invoke ``LoginIDCollectUIState/onLoginIDChange`` as the user edits,
    /// ``LoginIDCollectUIState/onContinue`` when the user submits the value, and
    /// ``LoginIDCollectUIState/onCancel`` when the user dismisses the form. `onContinue` asks the operation to validate
    /// and either settle with a validated login ID or publish a new error in `uiState`; `onCancel` settles the operation
    /// as user-close cancellation.
    @MainActor func content(
        uiState: LoginIDCollectUIState,
        uiStrings: LoginIDCollectStrings,
        errorTextProvider: ((ErrorCode) -> String)?,
        isReadyForInitialFocus: Bool
    ) -> AnyView
}
