import Foundation
import UIKit

/// Runs the OwnID Elite web-based authentication flow inside a WebView.
///
/// Starting the operation returns a ``WebBridgeOperationController`` whose state stream lets SDK-owned UI and callers
/// observe the operation lifecycle.
///
/// The operation resolves the WebView content, loads it into SDK-owned UI, and bridges hosted flow events to app-owned
/// native callbacks through ``WebBridgeOperationEventWrapper``. Callback failures are reported to the web flow as bridge
/// errors; the native operation is settled only after a terminal callback completes successfully.
///
/// Hosted terminal events such as `onFinish`, `onError`, `onClose`, and `onNativeAction` complete the operation with
/// ``OperationResult/success(_:)`` after the app callback returns. User close, WebView detach,
/// ``OperationController/abort(reason:)``, and SDK-initiated cancellation complete with ``OperationResult/canceled(_:)``.
/// Invalid resolved base URL/origin, UI startup failures, bridge injection failures, JavaScript load/exception
/// callbacks, WebView navigation failures, and WebView render-process termination complete with
/// ``OperationResult/failure(_:)``.
///
/// Base URL, HTML, User-Agent, inspectability, background, and WebView configuration values are resolved from
/// ``WebBridgeOperationParams``, OwnID configuration, local runtime information, and SDK defaults.
/// ``WebBridgeOperationParams/onBaseUrlResolved`` receives the resolved base URL before UI startup.
///
/// The resolved base URL must produce an origin. That origin is used as an explicit WebBridge origin rule and is
/// combined with server-configured allowed origins by the WebBridge. Messages from untrusted origins are not accepted.
/// SDK-managed WebBridge UI keeps the hosted flow document in the WebView, blocks local/script schemes, and opens
/// external navigations outside the embedded flow.
internal protocol WebBridgeOperation: OperationCapability, Sendable
where
    Params == WebBridgeOperationParams,
    Result == Void,
    Failure == WebBridgeOperationFailure
{}

/// Parameters for ``WebBridgeOperation``.
///
/// All parameters default to `nil` or empty.
internal struct WebBridgeOperationParams: CapabilityParams {
    /// Display and content options for the WebView. Defaults to `nil`, which lets the operation use server WebView
    /// configuration, local runtime information, and SDK defaults.
    internal let options: WebBridgeOperationOptions?
    /// App-owned event handlers that map hosted WebBridge actions to native callbacks. Defaults to an empty array.
    internal let eventWrappers: [any WebBridgeOperationEventWrapper]
    /// Best-effort callback invoked with the resolved base URL for the HTML page. Defaults to `nil`.
    ///
    /// The callback runs before UI startup and does not affect operation settlement.
    internal let onBaseUrlResolved: (@Sendable (String) -> Void)?

    internal init(
        options: WebBridgeOperationOptions? = nil,
        eventWrappers: [any WebBridgeOperationEventWrapper] = [],
        onBaseUrlResolved: (@Sendable (String) -> Void)? = nil
    ) {
        self.options = options
        self.eventWrappers = eventWrappers
        self.onBaseUrlResolved = onBaseUrlResolved
    }
}

/// Display and content options for the WebView-based OwnID Elite flow.
///
/// Use these options to override HTML content, base URL, User-Agent string, Web Inspector availability, background
/// color, and WebView configuration. Content values fall back to OwnID app configuration, local runtime information,
/// and then SDK defaults.
internal struct WebBridgeOperationOptions: Sendable {
    /// Base URL for the HTML page. Defaults to `nil`.
    ///
    /// The operation must be able to derive an origin from this value. Page URLs are accepted; path, query, and
    /// fragment are ignored for origin matching. Invalid values fail the operation before UI presentation.
    internal var baseUrl: String?

    /// Raw HTML to render with `WKWebView.loadHTMLString(_:baseURL:)`, using the resolved ``baseUrl``. Defaults to `nil`.
    internal var html: String?

    /// Custom WebView User-Agent string. Defaults to `nil`.
    internal var userAgent: String?

    /// If `true`, the WebView can be inspected with Safari Web Inspector on supported OS versions. Defaults to
    /// `false` when an options value is supplied.
    ///
    /// When ``WebBridgeOperationOptions`` is omitted entirely, the operation uses ``LocalInfo/isDebuggable``.
    internal var webViewIsInspectable: Bool

    /// Background color for the SDK-managed WebView container and safe-area regions. `nil` uses the SDK default.
    internal var backgroundColor: UIColor?

    /// If `true`, the SDK-managed WebView limits navigation to app-bound domains on iOS 14 and later. The value must
    /// be known before the `WKWebView` is created. Defaults to `false`.
    internal var limitsNavigationsToAppBoundDomains: Bool

    internal init(
        baseUrl: String? = nil,
        html: String? = nil,
        userAgent: String? = nil,
        webViewIsInspectable: Bool = false,
        backgroundColor: UIColor? = nil,
        limitsNavigationsToAppBoundDomains: Bool = false
    ) {
        self.baseUrl = baseUrl
        self.html = html
        self.userAgent = userAgent
        self.webViewIsInspectable = webViewIsInspectable
        self.backgroundColor = backgroundColor
        self.limitsNavigationsToAppBoundDomains = limitsNavigationsToAppBoundDomains
    }
}

/// Wraps a customer-provided callback for a single WebView event in the OwnID Elite flow.
///
/// Each wrapper maps a ``webBridgePluginAction`` name from the hosted flow to a native async function owned by the app
/// or SDK operation.
///
/// When ``isTerminal`` is `true`, a successful callback result closes the WebView and completes the operation with
/// ``OperationResult/success(_:)``. If the callback throws or its payload cannot be decoded, the hosted flow receives a
/// bridge error and the native operation remains active until another terminal event, cancellation, or failure occurs.
internal protocol WebBridgeOperationEventWrapper: Sendable {

    /// The WebView bridge action name this wrapper handles.
    var webBridgePluginAction: String { get }

    /// If `true`, the WebView closes after this event completes.
    var isTerminal: Bool { get }

    /// Invokes the wrapped callback with the given JSON parameters.
    ///
    /// - Parameters:
    ///   - params: JSON-encoded event payload, or `nil` if the event carries no data.
    ///   - coder: JSON encoder/decoder for payload serialization.
    /// - Returns: A ``JSONValue`` result passed back to the WebView.
    func runWrappedFunction(params: String?, coder: any JSONCoder) async throws -> JSONValue
}

/// Handles the `onNativeAction` event.
///
/// This terminal event is triggered when the hosted flow requires app-owned native handling. The operation closes the
/// WebView and settles successfully after the callback returns.
internal actor OnNativeActionWrapper: WebBridgeOperationEventWrapper {
    internal nonisolated let webBridgePluginAction: String = "onNativeAction"
    internal nonisolated let isTerminal: Bool = true

    private let onNativeAction: @MainActor (_ loginId: String, _ ownIdData: String?, _ accessToken: AccessToken?) async -> Void

    private struct Payload: Decodable {
        fileprivate let loginId: String
        fileprivate let ownIdData: String?
        fileprivate let authToken: String?
    }

    internal init(
        onNativeAction: @MainActor @escaping (_ loginId: String, _ ownIdData: String?, _ accessToken: AccessToken?) async -> Void
    ) {
        self.onNativeAction = onNativeAction
    }

    internal func runWrappedFunction(params: String?, coder: any JSONCoder) async throws -> JSONValue {
        guard let jsonParams = params else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unexpected: params=null"))
        }
        let payload = try coder.decodeFromString(jsonParams, as: Payload.self)
        await onNativeAction(payload.loginId, payload.ownIdData, payload.authToken.map { AccessToken(token: $0) })
        return JSONValue(true)
    }
}

/// Handles the `onFinish` event.
///
/// This terminal event is triggered when the hosted authentication flow completes successfully. The operation closes the
/// WebView and settles successfully after the callback returns.
internal actor OnFinishWrapper: WebBridgeOperationEventWrapper {
    internal nonisolated static let empty = OnFinishWrapper(
        onFinish: { @MainActor (_: String, _: AuthMethod, _: AccessToken?) async -> Void in }
    )

    internal nonisolated let webBridgePluginAction: String = "onFinish"
    internal nonisolated let isTerminal: Bool = true

    private let onFinish: @MainActor (_ loginId: String, _ authMethod: AuthMethod, _ accessToken: AccessToken?) async -> Void

    private struct Payload: Decodable {
        fileprivate let loginId: String
        // Unused let source: String // 'mobile' : 'desktop'
        // Unused let context: String? // OwnIdContext
        fileprivate let authMethod: AuthMethod
        fileprivate let authToken: String?

        // authType - legacy from version 3.x
        private enum CodingKeys: String, CodingKey { case loginId, authMethod, authType, authToken }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.loginId = try container.decode(String.self, forKey: .loginId)
            self.authToken = try container.decodeIfPresent(String.self, forKey: .authToken)

            if let method = try container.decodeIfPresent(AuthMethod.self, forKey: .authMethod) {
                self.authMethod = method
            } else if let legacy = try container.decodeIfPresent(AuthMethod.self, forKey: .authType) {
                self.authMethod = legacy
            } else {
                throw DecodingError.keyNotFound(
                    CodingKeys.authMethod,
                    DecodingError.Context(codingPath: container.codingPath, debugDescription: "Missing 'authMethod' (or legacy 'authType')")
                )
            }
        }
    }

    internal init(onFinish: @MainActor @escaping (_ loginId: String, _ authMethod: AuthMethod, _ accessToken: AccessToken?) async -> Void) {
        self.onFinish = onFinish
    }

    internal func runWrappedFunction(params: String?, coder: any JSONCoder) async throws -> JSONValue {
        guard let params else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unexpected: params=null"))
        }
        let payload: Payload = try coder.decodeFromString(params, as: Payload.self)
        let accessToken = payload.authToken.map { AccessToken(token: $0) }
        await onFinish(payload.loginId, payload.authMethod, accessToken)
        return JSONValue(true)
    }
}

/// Handles the `onError` event.
///
/// This terminal event is triggered when the hosted flow reports an application-level error. The operation closes the
/// WebView and settles successfully after the callback returns; the error string is delivered to the app callback.
internal actor OnErrorWrapper: WebBridgeOperationEventWrapper {
    internal nonisolated static let empty = OnErrorWrapper(onError: { @MainActor (_: String?) async -> Void in })

    internal nonisolated let webBridgePluginAction: String = "onError"
    internal nonisolated let isTerminal: Bool = true

    private let onError: @MainActor (_ error: String?) async -> Void

    internal init(onError: @MainActor @escaping (_ error: String?) async -> Void) {
        self.onError = onError
    }

    internal func runWrappedFunction(params: String?, coder: any JSONCoder) async throws -> JSONValue {
        await onError(params)
        return JSONValue(true)
    }
}

/// Handles the `onClose` event.
///
/// This terminal event is triggered when the hosted flow reports a close event. The operation closes the WebView and
/// settles successfully after the callback returns. Native user-close controls use ``OperationResult/canceled(_:)``
/// instead.
internal actor OnCloseWrapper: WebBridgeOperationEventWrapper {
    internal nonisolated static let empty = OnCloseWrapper(onClose: { @MainActor () async -> Void in })

    internal nonisolated let webBridgePluginAction: String = "onClose"
    internal nonisolated let isTerminal: Bool = true

    private let onClose: @MainActor () async -> Void

    internal init(onClose: @MainActor @escaping () async -> Void) {
        self.onClose = onClose
    }

    internal func runWrappedFunction(params: String?, coder: any JSONCoder) async throws -> JSONValue {
        await onClose()
        return JSONValue(true)
    }
}

/// Controller for an active ``WebBridgeOperation``.
///
/// SDK-owned WebBridge presentation observes this state stream to render the current WebView session and react to
/// completion. The stream progresses from ``WebBridgeOperationState/created`` to
/// ``WebBridgeOperationState/active(uiState:)`` and then to ``WebBridgeOperationState/completed(result:)``. Integrators
/// typically keep the returned controller to await settlement or cancel the operation.
internal protocol WebBridgeOperationController: OperationController<Void, WebBridgeOperationFailure> {
    /// Returns the observable lifecycle and UI state for this WebBridge operation.
    @MainActor func stateStream() -> AsyncStream<WebBridgeOperationState>
}

/// Failure payload returned by the SDK-managed WebBridge operation.
internal enum WebBridgeOperationFailure: OperationFailure, CustomStringConvertible {
    /// UI failure payload produced by WebBridge presentation or WebView runtime.
    internal struct UI: Sendable, CustomStringConvertible {
        internal let errorCode: ErrorCode
        internal let message: String
        internal let underlyingError: (any Error & Sendable)?

        internal init(
            errorCode: ErrorCode,
            message: String,
            underlyingError: (any Error & Sendable)? = nil
        ) {
            self.errorCode = errorCode
            self.message = message
            self.underlyingError = underlyingError
        }

        internal var description: String { "UI(errorCode=\(errorCode), message=\(message))" }
    }

    /// - About: The web bridge operation could not start because required local configuration or runtime preconditions are missing.
    /// - End-user: No direct user action. The app should offer another available path.
    /// - Developer action: Check WebView options, resolved base URL, HTML configuration, and bridge setup before starting
    ///   the operation.
    case precondition(errorCode: ErrorCode, message: String)
    /// - About: The WebView UI failed while loading or running the web bridge flow.
    /// - End-user: Show a generic unavailable state or let the user retry opening the web flow.
    /// - Developer action: Inspect WebView lifecycle, render-process state, bridge events, and `underlyingError`.
    /// - Diagnostics: `underlyingError` retains WebView/runtime error context when available.
    case ui(UI)
    /// - About: The operation stopped because of an unexpected SDK/runtime failure or an internal invariant violation.
    /// - End-user: Show a generic failure state. Retrying may be reasonable if the app can safely restart the web flow.
    /// - Developer action: Log operation context and inspect `underlyingError` before retrying automatically.
    case unexpected(errorCode: ErrorCode = .unknown, message: String, underlyingError: (any Error & Sendable)? = nil)

    var errorCode: ErrorCode {
        switch self {
        case .precondition(let errorCode, _),
            .unexpected(let errorCode, _, _):
            return errorCode
        case .ui(let ui):
            return ui.errorCode
        }
    }

    var message: String {
        switch self {
        case .precondition(_, let message),
            .unexpected(_, let message, _):
            return message
        case .ui(let ui):
            return ui.message
        }
    }

    var description: String {
        switch self {
        case .precondition:
            return "Precondition(errorCode=\(errorCode), message=\(message))"
        case .ui:
            return "UI(errorCode=\(errorCode), message=\(message))"
        case .unexpected:
            return "Unexpected(errorCode=\(errorCode), message=\(message))"
        }
    }

    var underlyingError: (any Error & Sendable)? {
        switch self {
        case .precondition: return nil
        case .ui(let ui): return ui.underlyingError
        case .unexpected(_, _, let underlyingError): return underlyingError
        }
    }
}

/// State machine for ``WebBridgeOperation``.
///
/// States progress from ``created`` through ``active(uiState:)`` to ``completed(result:)`` with an ``OperationResult``.
/// A settled operation does not emit another terminal state.
internal enum WebBridgeOperationState: OperationState {
    /// Initial state before the operation starts.
    case created
    /// The WebView UI has been requested and the web-based flow is in progress.
    case active(uiState: WebBridgeUIState)
    /// The operation finished with a success, cancellation, or failure result.
    case completed(result: OperationResult<Void, WebBridgeOperationFailure>)
}

extension WebBridgeOperationState: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.created, .created),
            (.active, .active),
            (.completed, .completed):
            return true
        default:
            return false
        }
    }
}
