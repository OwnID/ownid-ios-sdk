import Foundation

/// Web-based authentication flow that renders OwnID's hosted page inside an SDK-managed WebView.
///
/// - Call ``start(_:)`` with an optional ``EliteFlowContext`` to configure Elite Flow options and event handlers.
/// - The SDK resolves the WebView content from the context, OwnID configuration, and SDK defaults, then bridges
///   hosted-page events to native handlers.
/// - The app does not provide an access token, proof token, or headless flag when starting this flow. Tokens are
///   caller-visible only when the hosted page sends an access token to ``EliteFlowContext`` callbacks.
/// - Functional outcomes are delivered through hosted-page event handlers. The returned ``EliteFlowController`` is a
///   high-level handle for awaiting settlement, canceling the running WebView flow, or detecting infrastructure
///   failures.
/// - Event handlers (onFinish, onError, onClose, onNativeAction) are configured through
///   ``EliteFlowContext.Builder/events(_:)``.
///
/// The SDK owns `WKWebView` presentation and dismissal. The app owns the returned controller and any native callback
/// work started from the context. The SDK does not create an app session from hosted callbacks; handle any session
/// handoff at the app authentication boundary.
///
/// Terminal event handlers close the WebView and settle the controller with ``FlowResult/success(_:)`` after the
/// handler returns, including hosted `onError` and `onClose` events. ``FlowResult/failure(_:)`` is reserved for SDK or
/// WebBridge failures, such as a missing WebBridge operation or a WebView-level failure. ``FlowResult/canceled(_:)``
/// is used when the app aborts the controller, the SDK is shut down, or the WebView is canceled before a terminal
/// hosted-page event completes.
///
/// The caller owns the returned controller. Keep it strongly referenced while the flow is active.
///
/// Use ``EliteFlowController/abort(reason:)`` for semantic cancellation when you have an explicit reason that should
/// be propagated to the terminal result. If the owner is torn down while the flow is still active, abort the flow
/// with an appropriate ``Reason``.
public protocol EliteFlow: FlowCapability, Sendable {

    /// Starts the Elite flow with the given context.
    ///
    /// - Parameter context: Configuration for Elite Flow options and event handlers.
    /// - Returns: A controller to await settlement, cancel the flow, or detect SDK/WebBridge failures.
    ///
    /// The caller owns the returned controller and should abort it when the owner lifecycle ends while the flow is
    /// still active. Repeated calls on the same flow instance return the same controller and do not start a second run.
    /// Pass ``EliteFlowContext/empty`` or use ``start()`` for default WebView configuration and default hosted-page
    /// terminal handlers.
    func start(_ context: EliteFlowContext) -> any EliteFlowController
}

/// Controls a running Elite flow.
///
/// - Call ``whenSettled()`` to await the cached terminal ``FlowResult``.
/// - Use ``abort(reason:)`` for semantic cancellation with an explicit ``Reason``.
///
/// Handle functional outcomes in ``EliteFlowContext`` event handlers (`onFinish`, `onNativeAction`, `onError`,
/// `onClose`). ``whenSettled()`` is most useful for cleanup and for reacting to ``FlowResult/failure(_:)`` or
/// ``FlowResult/canceled(_:)``.
///
/// The caller owns this controller. Keep it strongly referenced while the flow is active, and abort it if the owner
/// is torn down before settlement.
///
/// Cancellation is best-effort. Calling ``abort(reason:)`` after settlement is safe and has no effect.
public protocol EliteFlowController: Sendable {
    /// Requests flow cancellation with an explicit `reason`.
    ///
    /// Use this API when cancellation semantics are meaningful to the caller and should be reflected in the terminal result.
    ///
    /// If the flow is already settled, this call has no effect.
    func abort(reason: Reason)
    /// Awaits the flow's completion and returns the cached ``FlowResult``.
    func whenSettled() async -> FlowResult<Void, EliteFlowFailure>
}

extension FlowController: EliteFlowController where Success == Void, Failure == EliteFlowFailure {}

extension EliteFlow {
    /// Starts the Elite flow with a default empty context.
    ///
    /// The caller owns the returned controller and should abort it when the owner lifecycle ends while the flow is still active.
    public func start() -> any EliteFlowController {
        start(.empty)
    }
}

/// Failure payload returned by ``EliteFlow``.
///
/// Every failure is terminal for the current Elite flow run. Hosted-page business outcomes are delivered through
/// ``EliteFlowContext`` event handlers. Flow failures are reserved for SDK/WebBridge setup, operation, or runtime
/// failures that prevent the native WebBridge flow from completing normally.
public enum EliteFlowFailure: FlowFailure, CustomStringConvertible {
    /// - About: The WebBridge operation could not run, was unavailable, or completed with failure.
    /// - End-user: End this web authentication attempt and show an unavailable state or a new-start retry option.
    /// - Developer action: Do not continue this flow controller. Inspect WebBridge configuration, container/UI setup,
    ///   allowed origins, and `operationFailure` when present. If `operationID` is absent, inspect `message` for startup
    ///   or missing dependency diagnostics.
    /// - Diagnostics: `operationType` is the failed operation step, `operationID` identifies a started WebBridge
    ///   operation, and `operationFailure` or `underlyingError` retains lower-level context when available.
    case operationFailed(
        operationType: OperationType = .webBridge,
        errorCode: ErrorCode,
        message: String,
        operationID: OperationID? = nil,
        operationFailure: (any OperationFailure)? = nil,
        underlyingError: (any Error & Sendable)? = nil
    )
    /// - About: The flow stopped because of an unexpected SDK/runtime failure or an internal invariant violation.
    /// - End-user: End this web authentication attempt and show a generic failure state.
    /// - Developer action: Log flow context and `underlyingError`, then inspect WebBridge setup and hosted event handling
    ///   before starting a new attempt.
    case unexpected(errorCode: ErrorCode = .unknown, message: String, underlyingError: (any Error & Sendable)? = nil)

    private var payload: (ErrorCode, String) {
        switch self {
        case .operationFailed(_, let errorCode, let message, _, _, _),
            .unexpected(let errorCode, let message, _):
            return (errorCode, message)
        }
    }

    public var errorCode: ErrorCode { payload.0 }
    public var message: String { payload.1 }
    public var description: String {
        switch self {
        case .operationFailed:
            return "OperationFailed(errorCode=\(errorCode), message=\(message))"
        case .unexpected:
            return "Unexpected(errorCode=\(errorCode), message=\(message))"
        }
    }
}
