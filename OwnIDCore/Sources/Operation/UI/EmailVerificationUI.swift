import Foundation

/// UI capability for the email verification operation.
///
/// Presents or binds UI for an active ``EmailVerificationOperation``.
///
/// The operation owns the challenge, timeout, final settlement, and controller callbacks. UI implementations render
/// ``EmailVerificationUIState``, invoke its callbacks for code entry, resend, cancel, and "not you", and report startup
/// or presentation failure from ``start(controller:)``. They should not create a separate verification lifecycle.
///
/// If no UI implementation is registered, startup fails and the operation reports a UI integration failure.
public protocol EmailVerificationUI: AnyObject, OperationUI {
    /// Starts the UI for email verification, binding it to the given `controller`.
    ///
    /// Implementations should present UI for the running operation identified by ``OperationController/operationID`` and
    /// observe ``EmailVerificationOperationController/stateStream()`` when they need ``EmailVerificationUIState`` updates.
    /// The operation remains the owner of challenge completion, cancellation, timeout, and final result settlement.
    ///
    /// Implementations must not throw from this method.
    /// Report recoverable startup or presentation failures by returning an ``EmailVerificationOperationFailure/Integration``.
    ///
    /// - Parameter controller: The operation controller to bind UI actions to.
    /// - Returns: An error if the UI fails to start, or `nil` on success.
    @MainActor func start(controller: any EmailVerificationOperationController) -> EmailVerificationOperationFailure.Integration?
}

/// Observable state for the email verification UI.
///
/// ``challenge`` describes the current challenge, including where the code was sent. ``isBusy`` indicates that the
/// operation is processing a user action. ``error`` is displayable user-facing error state; wrong-code and resend-limit
/// responses stay in this UI state instead of completing the operation.
///
/// Invoke callbacks only in response to user intent. ``onCodeEntered`` submits a code. ``onResend`` requests another code
/// when the UI allows it. ``onCancel`` dismisses the current verification attempt. ``onNotYou`` tells the operation to
/// move away from the selected challenge. Operation settlement is owned by the operation.
///
/// - ``challenge``: The current verification challenge.
/// - ``isBusy``: If `true`, the UI should show a loading indicator and avoid duplicate non-cancel actions.
/// - ``error``: A validation or OwnID error to display, or `nil` if none.
/// - ``onCodeEntered``: Callback to invoke when the user submits a verification code.
/// - ``onCancel``: Callback to invoke when the user dismisses the UI.
/// - ``onNotYou``: Callback to invoke when the user indicates this is not their email.
/// - ``onResend``: Callback to invoke when the user requests a new code.
public struct EmailVerificationUIState: Equatable, Sendable {
    /// The selected verification challenge details.
    public let challenge: VerificationChallenge
    /// If `true`, the UI should show a loading indicator.
    public let isBusy: Bool
    /// A validation or OwnID error to display, or `nil` if none.
    public let error: UIError?
    /// Callback to invoke when the user submits a verification code.
    public let onCodeEntered: @Sendable (String) -> Void
    /// Callback to invoke when the user dismisses the UI.
    public let onCancel: @Sendable () -> Void
    /// Callback to invoke when the user indicates this is not their email.
    public let onNotYou: @Sendable () -> Void
    /// Callback to invoke when the user requests a new code.
    public let onResend: @Sendable () -> Void

    /// Creates email verification UI state.
    ///
    /// - Parameters:
    ///   - challenge: Verification challenge details.
    ///   - isBusy: Indicates whether the UI should show a loading state. Defaults to `false`.
    ///   - error: Validation or OwnID error to display. Defaults to `nil`.
    ///   - onCodeEntered: Callback invoked when the user submits a verification code.
    ///   - onCancel: Callback invoked when the user dismisses the UI.
    ///   - onNotYou: Callback invoked when the user indicates this is not their email.
    ///   - onResend: Callback invoked when the user requests a new code.
    public init(
        challenge: VerificationChallenge,
        isBusy: Bool = false,
        error: UIError? = nil,
        onCodeEntered: @escaping @Sendable (String) -> Void,
        onCancel: @escaping @Sendable () -> Void,
        onNotYou: @escaping @Sendable () -> Void,
        onResend: @escaping @Sendable () -> Void
    ) {
        self.challenge = challenge
        self.isBusy = isBusy
        self.error = error
        self.onCodeEntered = onCodeEntered
        self.onCancel = onCancel
        self.onNotYou = onNotYou
        self.onResend = onResend
    }

    public static func == (lhs: EmailVerificationUIState, rhs: EmailVerificationUIState) -> Bool {
        lhs.challenge == rhs.challenge && lhs.isBusy == rhs.isBusy && lhs.error == rhs.error
    }
}

internal final class NoopEmailVerificationUI: EmailVerificationUI {
    @MainActor
    func start(controller: any EmailVerificationOperationController) -> EmailVerificationOperationFailure.Integration? {
        .ui(
            errorCode: .integrationError,
            message: "No UI implementation registered for EmailVerificationUI. Add OwnID UI or register a custom EmailVerificationUI."
        )
    }
}
