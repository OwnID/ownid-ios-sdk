import SwiftUI
import UIKit
import WebKit

/// UI capability for the OwnID web-based flow.
///
/// Presents a `WKWebView` for a running ``WebBridgeOperation`` and binds the displayed content to the supplied
/// controller. The UI layer owns iOS presentation, WebView navigation policy, and platform startup errors; operation
/// settlement remains owned by ``WebBridgeOperation``.
///
/// SDK-managed WebBridge UI keeps the OwnID flow document in the embedded WebView, blocks local/script schemes, opens
/// external navigations outside the flow, and reports JavaScript bootstrap failures, render-process loss, and navigation
/// failures through the operation callbacks in ``WebBridgeUIState``.
internal protocol WebBridgeUI: OperationUI {
    /// Starts the UI for the given WebBridge operation.
    ///
    /// Implementations should present the web-based flow for the running operation identified by
    /// ``OperationController/operationID`` and wire the visible WebView to the current ``WebBridgeUIState``.
    ///
    /// Implementations must not throw from this method.
    /// Report immediate startup failures by returning a ``WebBridgeOperationFailure/UI``.
    /// Report delayed presentation failures through `onStartError`.
    ///
    /// - Parameters:
    ///   - controller: The operation controller to bind the UI to.
    ///   - webViewConfiguration: Values that must be applied before the `WKWebView` instance is created.
    ///   - onDetach: Callback invoked after the WebView is removed from the view hierarchy. The operation uses it to
    ///     detach the bridge and, when the operation is still active, cancel with user-close semantics.
    ///   - onStartError: Callback invoked when the UI fails after `start(...)` has already returned.
    /// - Returns: An error if the UI cannot be started immediately, or `nil` when startup was accepted.
    @MainActor
    func start(
        controller: any WebBridgeOperationController,
        webViewConfiguration: WebBridgeWebViewConfiguration,
        onDetach: @MainActor @escaping () -> Void,
        onStartError: @MainActor @escaping (WebBridgeOperationFailure.UI) -> Void
    ) -> WebBridgeOperationFailure.UI?
}

/// Configuration values that must be known before the SDK-managed `WKWebView` is created.
internal struct WebBridgeWebViewConfiguration: Sendable, Equatable {
    /// If `true`, the `WKWebViewConfiguration` limits navigation to app-bound domains on iOS 14 and later.
    ///
    /// This is a WebKit construction-time option and has no effect on an already-created `WKWebView`.
    internal let limitsNavigationsToAppBoundDomains: Bool

    internal static let `default` = WebBridgeWebViewConfiguration()

    internal init(limitsNavigationsToAppBoundDomains: Bool = false) {
        self.limitsNavigationsToAppBoundDomains = limitsNavigationsToAppBoundDomains
    }
}

/// Observable state for the WebBridge UI.
///
/// Contains the web content to display and the callbacks to invoke for user actions and terminal WebView events.
internal struct WebBridgeUIState: Sendable {
    /// Base URL passed to `WKWebView.loadHTMLString(_:baseURL:)` for the HTML page and used to derive the WebBridge
    /// page origin.
    internal let baseUrl: String
    /// Raw HTML rendered by the SDK-owned WebView.
    internal let html: String
    /// User-Agent string applied to the WebView before loading.
    internal let userAgent: String
    /// If `true`, the WebView can be inspected with Safari Web Inspector on supported OS versions.
    internal let webViewIsInspectable: Bool?
    /// Background color for the SDK-managed WebView container and safe-area regions, or `nil` for the SDK default.
    internal let backgroundColor: UIColor?
    /// Callback that prepares WebBridge communication for a `WKWebView` before HTML load. Attachment failures
    /// must be reported through ``onWebViewTerminalError``.
    internal var doWebViewBridgeInject: @MainActor @Sendable (WKWebView) throws -> Void
    /// Callback invoked for unrecoverable WebView/bridge errors, JavaScript bootstrap failures, render-process
    /// termination, or HTML load failures.
    internal var onWebViewTerminalError: @MainActor @Sendable ((any Error)?, String?) -> Void
    /// Callback invoked when the user cancels or closes the WebView flow.
    internal var onWebViewCancel: @MainActor @Sendable (Reason) -> Void

    internal init(
        baseUrl: String,
        html: String,
        userAgent: String,
        webViewIsInspectable: Bool,
        backgroundColor: UIColor?,
        doWebViewBridgeInject: @MainActor @Sendable @escaping (WKWebView) throws -> Void,
        onWebViewTerminalError: @MainActor @Sendable @escaping ((any Error)?, String?) -> Void,
        onWebViewCancel: @MainActor @Sendable @escaping (Reason) -> Void
    ) {
        self.baseUrl = baseUrl
        self.html = html
        self.userAgent = userAgent
        self.webViewIsInspectable = webViewIsInspectable
        self.backgroundColor = backgroundColor

        self.doWebViewBridgeInject = doWebViewBridgeInject
        self.onWebViewTerminalError = onWebViewTerminalError
        self.onWebViewCancel = onWebViewCancel
    }
}
