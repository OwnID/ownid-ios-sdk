import Foundation

/// Collects a login ID from the user.
///
/// Use this operation when the app needs the user to provide the identifier for the next OwnID step. The SDK first uses
/// the typed ``LoginIDCollectOperationParams/loginID`` supplied by the app, then a typed login ID from the current
/// OwnID ``Context``, then a raw login ID string from the current context. If the resolved typed value is valid and
/// collectable, the operation completes successfully without showing a form. If the value is missing or invalid but can
/// be corrected, the SDK opens login ID collection UI.
///
/// When multiple login ID types are collectable, the user enters a single value and the SDK validates it against those
/// collectable types in the configured priority order.
///
/// If the UI is shown, the operation cancels with ``Reason/timeout`` after five minutes. User dismissal through the UI
/// cancels with ``Reason/userClose(details:)``. Calling ``OperationController/abort(reason:)`` cancels with the supplied
/// reason. Requests made after the operation has settled do not change the terminal result. Abort explicitly when an
/// owner lifecycle ends while the operation is still active.
///
/// This operation collects ``LoginIDType/email``, ``LoginIDType/phoneNumber``, and ``LoginIDType/userName``.
/// On success, the result contains the validated ``LoginID``. When no collectable types are available, UI startup
/// fails, a resolved typed login ID has an unsupported type, or an unexpected SDK/runtime error occurs, the operation
/// completes with ``OperationResult/failure(_:)`` carrying ``LoginIDCollectOperationFailure``.
///
/// ``availability(params:)`` returns available when at least one collectable login ID type is configured and any
/// supplied typed login ID has a collectable type. Invalid collectable values do not make the operation unavailable
/// because the UI can let the user correct them.
///
/// If no UI implementation is registered, startup fails and the operation completes with
/// ``OperationResult/failure(_:)``.
///
/// Keep the returned controller strongly referenced while the operation is active.
///
/// If you need to stop an active operation, call ``OperationController/abort(reason:)``.
/// For advanced UI integrations, cast the returned controller to ``LoginIDCollectOperationController`` and observe
/// ``LoginIDCollectOperationController/stateStream()``.
public protocol LoginIDCollectOperation: OperationCapability, Sendable
where
    Params == LoginIDCollectOperationParams,
    Result == LoginID,
    Failure == LoginIDCollectOperationFailure
{}

/// Parameters for ``LoginIDCollectOperation``.
///
/// ``loginID`` provides a typed login ID supplied by the app. If it is valid, the operation completes without showing
/// UI. If the type is supported but the value is invalid, the form opens with ``LoginID/id`` so the user can correct it.
/// This value takes precedence over typed and raw login ID values from the current OwnID context. When `nil`, a typed
/// context login ID is used first, then a raw context login ID if present; otherwise the form starts blank.
/// ``onUIClick`` is invoked on Continue and Cancel taps when the UI is shown.
public struct LoginIDCollectOperationParams: CapabilityParams {
    /// A pre-filled login ID. Defaults to `nil`.
    public let loginID: LoginID?
    /// Callback invoked when the user taps Continue or Cancel, receiving the ``OperationID``. Defaults to `nil`.
    public let onUIClick: (@Sendable (OperationID) -> Void)?

    /// Creates login ID collection parameters.
    ///
    /// - Parameters:
    ///   - loginID: Pre-filled login ID. Defaults to `nil`.
    ///   - onUIClick: Callback invoked when the user taps Continue or Cancel. Defaults to `nil`.
    public init(
        loginID: LoginID? = nil,
        onUIClick: (@Sendable (OperationID) -> Void)? = nil
    ) {
        self.loginID = loginID
        self.onUIClick = onUIClick
    }
}

/// Controller contract for advanced ``LoginIDCollectOperation`` UI integrations.
///
/// ``start(params:)`` returns a general ``OperationController``. When host-managed UI needs access to state updates, cast
/// that controller to ``LoginIDCollectOperationController`` and observe ``stateStream()``. This is a dedicated
/// controller protocol, not a typealias to ``OperationController``, because login ID collection exposes public state for
/// UI binding.
public protocol LoginIDCollectOperationController: OperationController<LoginID, LoginIDCollectOperationFailure> {
    /// Emits state transitions for the running login ID collection operation on the main actor.
    ///
    /// The stream emits ``LoginIDCollectOperationState/created``,
    /// ``LoginIDCollectOperationState/active(uiState:)`` when UI is needed, and
    /// ``LoginIDCollectOperationState/completed(result:)``. The latest state is yielded to new observers.
    @MainActor func stateStream() -> AsyncStream<LoginIDCollectOperationState>
}

/// State emitted by ``LoginIDCollectOperationController/stateStream()``.
///
/// States progress from ``created`` to ``active(uiState:)`` only when login ID collection UI is visible, and finally to
/// ``completed(result:)``. Operations that can resolve a valid typed login ID from input or context may move directly
/// from ``created`` to ``completed(result:)`` with ``OperationResult/success(_:)``.
public enum LoginIDCollectOperationState: OperationState {
    /// Initial state before the operation starts.
    case created
    /// The collection UI is visible. `uiState` contains the current login ID text, collectable types, validation error, and action callbacks.
    case active(uiState: LoginIDCollectUIState)
    /// The operation finished with a validated login ID, a cancellation reason, or a typed failure payload.
    case completed(result: OperationResult<LoginID, LoginIDCollectOperationFailure>)
}

extension LoginIDCollectOperationState: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.created, .created): return true
        case (.active(let l), .active(let r)): return l == r
        case (.completed, .completed): return true
        default: return false
        }
    }
}

/// Failure payload returned by ``LoginIDCollectOperation``.
///
/// Every failure is terminal for the current operation run. Input failures indicate caller-supplied values that cannot
/// be accepted by this operation. Integration failures indicate missing configuration or UI capability problems.
/// ``unexpected(errorCode:message:underlyingError:)`` is reserved for unexpected SDK/runtime failures. Invalid but
/// collectable login ID values are presented in active UI for user correction instead of becoming terminal input
/// failures. Branch on the enum case and nested category to decide whether to adjust login-ID input, fix integration,
/// or offer another path; use ``OperationFailure/errorCode`` only as a localization key.
public enum LoginIDCollectOperationFailure: OperationFailure, CustomStringConvertible {
    /// Login ID supplied by the app has an unsupported type. Invalid values stay in the active UI for correction.
    public enum Input: Sendable, CustomStringConvertible {
        /// - About: The app supplied a login ID type that this collect operation cannot accept.
        /// - End-user: No direct user action. The app should ask for one of the configured supported identifier types.
        /// - Developer action: Pass only a collectable ``LoginID`` type or start the operation without a prefilled login ID.
        case unsupportedLoginIDType(errorCode: ErrorCode, message: String)

        public var errorCode: ErrorCode {
            switch self {
            case .unsupportedLoginIDType(let errorCode, _): return errorCode
            }
        }

        public var message: String {
            switch self {
            case .unsupportedLoginIDType(_, let message): return message
            }
        }

        public var description: String {
            "Input.UnsupportedLoginIDType(errorCode=\(errorCode), message=\(message))"
        }
    }

    /// SDK, app, backend, provider, or platform integration path failed.
    public enum Integration: Sendable, CustomStringConvertible {
        /// - About: The SDK could not determine any login ID type that can be collected.
        /// - End-user: No direct user action. The app should offer another sign-in or registration path.
        /// - Developer action: Check login ID type configuration and operation requirements before starting collection.
        case noSupportedLoginIDTypes(errorCode: ErrorCode, message: String)
        /// - About: The login ID collection UI failed before the operation could complete.
        /// - End-user: Show a generic unavailable state or let the user retry opening the collection UI.
        /// - Developer action: Inspect UI setup, window/presentation availability, and `underlyingError` for the concrete
        ///   UI failure.
        /// - Diagnostics: `underlyingError` retains UI/runtime error context when available.
        case ui(errorCode: ErrorCode, message: String, underlyingError: (any Error & Sendable)? = nil)

        public var errorCode: ErrorCode {
            switch self {
            case .noSupportedLoginIDTypes(let errorCode, _), .ui(let errorCode, _, _): return errorCode
            }
        }

        public var message: String {
            switch self {
            case .noSupportedLoginIDTypes(_, let message), .ui(_, let message, _): return message
            }
        }

        public var description: String {
            switch self {
            case .noSupportedLoginIDTypes:
                return "Integration.NoSupportedLoginIDTypes(errorCode=\(errorCode), message=\(message))"
            case .ui:
                return "Integration.UI(errorCode=\(errorCode), message=\(message))"
            }
        }
    }

    /// Login ID supplied by the app has an unsupported type.
    case input(Input)
    /// SDK, app, backend, provider, or platform integration path failed.
    case integration(Integration)
    /// - About: The operation stopped because of an unexpected SDK/runtime failure or an internal invariant violation.
    /// - End-user: Show a generic failure state. Retrying may be reasonable if the app can safely restart the operation.
    /// - Developer action: Log the failure with operation context and inspect `underlyingError` before retrying automatically.
    /// - Diagnostics: `underlyingError` retains runtime error context when available.
    case unexpected(errorCode: ErrorCode = .unknown, message: String, underlyingError: (any Error & Sendable)? = nil)

    public var errorCode: ErrorCode {
        switch self {
        case .input(let input): return input.errorCode
        case .integration(let integration): return integration.errorCode
        case .unexpected(let errorCode, _, _): return errorCode
        }
    }

    public var message: String {
        switch self {
        case .input(let input): return input.message
        case .integration(let integration): return integration.message
        case .unexpected(_, let message, _): return message
        }
    }

    public var description: String {
        switch self {
        case .input(let input):
            return "\(input)"
        case .integration(let integration):
            return "\(integration)"
        case .unexpected:
            return "Unexpected(errorCode=\(errorCode), message=\(message))"
        }
    }
}
