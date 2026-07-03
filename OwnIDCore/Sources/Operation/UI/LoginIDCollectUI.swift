import Foundation

/// UI capability for the login ID collection operation.
///
/// Drives a form where the user enters or confirms a login identifier of type
/// ``LoginIDType/email``, ``LoginIDType/phoneNumber``, or ``LoginIDType/userName``.
///
/// The operation owns settlement and validation. UI implementations own presentation, dismissal controls, input
/// rendering, and forwarding user actions through ``LoginIDCollectUIState`` callbacks. Calling the cancel callback
/// settles the operation as canceled with user-close semantics.
///
/// If no UI implementation is registered, startup fails and the operation reports a UI integration failure.
public protocol LoginIDCollectUI: AnyObject, OperationUI {
    /// Starts the UI for login ID collection, binding it to the given `controller`.
    ///
    /// Implementations should present UI for the running operation identified by ``OperationController/operationID``
    /// and bind user actions to the controller-backed operation state exposed elsewhere by the SDK. The UI should
    /// observe ``LoginIDCollectOperationController/stateStream()`` when it needs ongoing state updates.
    ///
    /// Implementations must not throw from this method.
    /// Report recoverable startup or presentation failures by returning a ``LoginIDCollectOperationFailure/Integration``.
    ///
    /// - Parameter controller: The operation controller to bind UI actions to.
    /// - Returns: An error if the UI fails to start, or `nil` on success.
    @MainActor func start(controller: any LoginIDCollectOperationController) -> LoginIDCollectOperationFailure.Integration?
}

/// Observable state for the login ID collection UI.
///
/// - ``loginIDValue``: The current login ID text entered by the user.
/// - ``collectableLoginIDTypes``: The login ID types this form can collect, in validation priority order.
/// - ``error``: A validation or OwnID error to display, or `nil` if none.
/// - ``onLoginIDChange``: Callback to invoke when the user changes the login ID text.
/// - ``onContinue``: Callback to invoke when the user submits the login ID for validation.
/// - ``onCancel``: Callback to invoke when the user dismisses the UI; the operation cancels with
///   ``Reason/userClose(details:)``.
///
/// The operation may update this state after validation, including clearing ``error`` when the user edits the value.
public struct LoginIDCollectUIState: Equatable, Sendable {
    /// The current login ID text entered by the user.
    public let loginIDValue: String
    /// The login ID types this form can collect, in validation priority order.
    public let collectableLoginIDTypes: [LoginIDType]
    /// A validation or OwnID error to display, or `nil` if none.
    public let error: UIError?
    /// Callback to invoke when the user changes the login ID text.
    public let onLoginIDChange: @Sendable (String) -> Void
    /// Callback to invoke when the user submits the login ID for validation.
    public let onContinue: @Sendable () -> Void
    /// Callback to invoke when the user dismisses the UI; the operation cancels with ``Reason/userClose(details:)``.
    public let onCancel: @Sendable () -> Void

    /// Creates login ID collection UI state.
    ///
    /// - Parameters:
    ///   - loginIDValue: Current login ID text entered by the user.
    ///   - collectableLoginIDTypes: Login ID types this form can collect, in validation priority order.
    ///   - error: Validation or OwnID error to display. Defaults to `nil`.
    ///   - onLoginIDChange: Callback invoked when the user changes the login ID text.
    ///   - onContinue: Callback invoked when the user submits the login ID for validation.
    ///   - onCancel: Callback invoked when the user dismisses the UI.
    public init(
        loginIDValue: String,
        collectableLoginIDTypes: [LoginIDType],
        error: UIError? = nil,
        onLoginIDChange: @Sendable @escaping (String) -> Void,
        onContinue: @Sendable @escaping () -> Void,
        onCancel: @Sendable @escaping () -> Void
    ) {
        self.loginIDValue = loginIDValue
        self.collectableLoginIDTypes = collectableLoginIDTypes
        self.error = error
        self.onLoginIDChange = onLoginIDChange
        self.onContinue = onContinue
        self.onCancel = onCancel
    }

    public static func == (lhs: LoginIDCollectUIState, rhs: LoginIDCollectUIState) -> Bool {
        return lhs.loginIDValue == rhs.loginIDValue
            && lhs.collectableLoginIDTypes == rhs.collectableLoginIDTypes
            && lhs.error == rhs.error
    }
}

internal final class NoopLoginIDCollectUI: LoginIDCollectUI {
    @MainActor
    func start(controller: any LoginIDCollectOperationController) -> LoginIDCollectOperationFailure.Integration? {
        .ui(
            errorCode: .integrationError,
            message: "No UI implementation registered for LoginIDCollectUI. Add OwnID UI or register a custom LoginIDCollectUI."
        )
    }
}
