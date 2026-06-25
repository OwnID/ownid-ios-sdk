import Foundation
import WebKit

/// Enables bidirectional communication between the OwnID Web SDK in a WKWebView and the native OwnID SDK.
///
/// The bridge installs JavaScript into the `WKWebView` and exposes SDK functionality through plugin namespaces such
/// as FIDO or STORAGE. Create a new bridge for each WKWebView session, customize ``plugins`` before
/// ``attach(webView:allowedOriginRules:)``, and call ``detach()`` when the web view lifecycle does not already release
/// the attached view.
public protocol WebBridge: Capability, Sendable {

    /// Bridge-scoped plugin registry.
    ///
    /// A new bridge starts with fresh plugin instances created from the namespace-level
    /// ``OwnIDWebBridge/defaultPluginFactories``. Use this registry to inspect or adjust the concrete plugin instances
    /// that will be injected by this bridge instance.
    /// ``WebBridge/attach(webView:allowedOriginRules:)`` uses a captured copy of the registry at injection time.
    ///
    /// Register fresh plugin instances for this bridge only; do not reuse a plugin instance that is already associated
    /// with another bridge or registry.
    var plugins: any WebBridgePluginRegistry { get }

    /// Injects the bridge into `webView` for the given `allowedOriginRules`.
    ///
    /// Usage and lifecycle:
    /// - Call before loading content, or reload the page after a successful injection, so the page sees the bridge
    ///   from document start.
    /// - Registers message handlers and document-start scripts on the web view. WebKit does not scope the user script
    ///   to specific origins, so the bridge validates the main-frame source origin before invoking plugins.
    /// - Normalizes explicit `allowedOriginRules`, merges them with the best currently available server
    ///   configuration `webView.allowedOrigins`, and exposes the resulting origin rules to plugins through
    ///   ``WebBridgePluginMessage/allowedOriginRules`` for subsequent bridge calls.
    /// - Cannot be reinjected after a successful injection. Create a fresh instance for each WKWebView session.
    /// - Must be called on the main actor.
    ///
    /// Allowed origin rules:
    /// - Accept entries in the form `scheme://host[:port]`, for example `https://example.com`,
    ///   `https://login.example.com:443`, or `https://[2001:db8::1]`.
    /// - Assume `https://` when the scheme is omitted.
    /// - Support DNS names, IPv4 literals, and bracketed IPv6 literals.
    /// - Allow subdomain wildcard rules only for DNS hosts.
    /// - Reject rules with userinfo, path, query, fragment, trailing-dot hosts, or empty ports.
    /// - Skip invalid rules and log them.
    /// - Fail injection when no valid rules remain after normalization.
    /// - Treat the global wildcard rule as allowing any origin; avoid it in production.
    ///
    /// When attaching very early during app startup, Server Configuration may not be fetched yet. In startup-sensitive
    /// integrations such as app-hosted WebView frameworks, pass required origins explicitly in `allowedOriginRules`,
    /// or wait for ``AppConfigProvider/getOrFetchConfig()`` before calling `attach` if you need server-provided
    /// origins deterministically.
    ///
    /// Failure behavior:
    /// - Returns `nil` on success.
    /// - Returns a ``WebBridgeError`` instead of throwing it.
    ///
    /// Plugins may enforce additional checks, such as main-frame-only handling or stricter origin validation.
    /// Allow only trusted origins.
    ///
    /// - Parameter webView: The web view to inject the bridge into.
    /// - Parameter allowedOriginRules: Explicit origins to merge first with the best currently available server
    ///   configuration `webView.allowedOrigins`. Injection fails only when the effective set is empty after
    ///   normalization.
    /// - Returns: `nil` on success, or a ``WebBridgeError`` on failure.
    @MainActor
    @discardableResult
    func attach(webView: WKWebView, allowedOriginRules: Set<String>) -> WebBridgeError?

    /// Detaches the bridge from the web view this bridge instance last attached to.
    ///
    /// This removes message handlers, clears the bridge's captured plugin set, and cancels pending tasks.
    /// If the original web view is already gone, the bridge uses its last known content controller when available.
    ///
    /// This does not remove previously added `WKUserScript` entries from the web view's `WKUserContentController`.
    /// After detach, remaining scripts cannot reach the removed native message handler. Use a fresh web view or
    /// configuration when the host requires script-list cleanup.
    @MainActor func detach()
}

extension WebBridge {
    /// Injects the bridge into `webView` using only the best currently available server configuration origins.
    ///
    /// This is equivalent to calling ``WebBridge/attach(webView:allowedOriginRules:)`` with an empty explicit
    /// `allowedOriginRules` set.
    ///
    /// - Parameter webView: The web view to inject the bridge into.
    /// - Returns: `nil` on success, or a ``WebBridgeError`` on failure.
    @MainActor
    @discardableResult
    public func attach(webView: WKWebView) -> WebBridgeError? {
        attach(webView: webView, allowedOriginRules: [])
    }
}

/// Error type returned by ``WebBridge/attach(webView:allowedOriginRules:)`` on failure.
public enum WebBridgeError: Swift.Error, LocalizedError {
    /// A general injection failure with an optional message and underlying error.
    case general(_ message: String?, _ error: (any Swift.Error)? = nil)

    /// A localized description for this error.
    ///
    /// Uses the explicit message when present, otherwise falls back to the underlying error description.
    public var errorDescription: String? {
        switch self {
        case .general(let message, let error):
            if let message = message, !message.isEmpty { return message }
            if let error = error { return error.localizedDescription }
            return "An unknown error occurred."

        }
    }
}
