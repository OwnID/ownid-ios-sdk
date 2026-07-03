import Foundation
import UIKit

internal struct EliteFlowContextKey<Value: Sendable>: Hashable, Sendable {
    internal let rawValue: String

    internal init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// Immutable configuration for the Elite web-based authentication flow.
///
/// Carries optional WebView options and event handlers (onFinish, onError, onClose, onNativeAction). The Elite flow
/// accepts WebView configuration only; it does not accept an app-provided access token, proof token, or headless flag.
/// Hosted-page callbacks may deliver an access token when the hosted flow sends one.
///
/// Build it via the ``init(_:)`` closure or ``Builder``, or use ``empty`` for default behavior. Configure WebView
/// display/content overrides through ``EliteFlowOptionsBuilder``. If you omit
/// ``EliteFlowEventBuilder/onFinish(_:)``, ``EliteFlowEventBuilder/onError(_:)``, or
/// ``EliteFlowEventBuilder/onClose(_:)``, default no-op hosted-page handlers are installed.
/// ``EliteFlowEventBuilder/onNativeAction(_:)`` is installed only when configured.
///
/// Hosted-page terminal handlers close the WebView after the handler returns and complete the flow; direct WebView
/// close/cancel events complete as cancellation. Custom terminal handlers run on the main actor and are responsible
/// only for app-side work; the SDK still owns WebView dismissal.
public struct EliteFlowContext: CustomStringConvertible, @unchecked Sendable {
    /// Creates an empty context with no overrides.
    ///
    /// The flow uses server WebView configuration and SDK defaults, installs no-op finish/error/close handlers, and
    /// does not register a native-action callback.
    public static let empty = EliteFlowContext()

    private var storage: [String: Any]

    internal init(storage: [String: Any]) {
        self.storage = storage
    }

    internal subscript<Value: Sendable>(_ key: EliteFlowContextKey<Value>) -> Value? {
        get { storage[key.rawValue] as? Value }
        set { storage[key.rawValue] = newValue }
    }

    /// Returns a builder pre-populated with this context's values for incremental modification.
    public func toBuilder() -> Builder {
        Builder(storage: storage)
    }

    /// DSL builder for ``EliteFlowContext``.
    ///
    /// Use ``options(_:)`` for ``EliteFlowOptionsBuilder`` overrides, and ``events(_:)`` for hosted-page callbacks.
    public struct Builder: @unchecked Sendable {
        private var storage: [String: Any]

        internal init(storage: [String: Any] = [:]) {
            self.storage = storage
        }

        internal subscript<Value: Sendable>(_ key: EliteFlowContextKey<Value>) -> Value? {
            get { storage[key.rawValue] as? Value }
            set { storage[key.rawValue] = newValue }
        }

        /// Creates an ``EliteFlowContext`` from the builder's current state.
        public func build() -> EliteFlowContext {
            EliteFlowContext(storage: storage)
        }

        internal mutating func resetEvents() {
            self[EliteFlowContextKeys.eventsWrappers] = []
        }

        internal mutating func addEvent(_ wrapper: any WebBridgeOperationEventWrapper) {
            var current = self[EliteFlowContextKeys.eventsWrappers] ?? []
            current.append(wrapper)
            self[EliteFlowContextKeys.eventsWrappers] = current
        }
    }

    /// Creates a context configured via a builder closure.
    ///
    /// Omitted options and events use ``empty`` behavior.
    ///
    /// - Parameter build: Closure that sets properties on a ``Builder``.
    public init(_ build: (inout Builder) -> Void = { _ in }) {
        var builder = Builder()
        build(&builder)
        self = builder.build()
    }

    /// A debug-oriented string that lists configured context keys and values.
    public var description: String {
        let entries = storage.map { (key, value) -> String in
            if ["ownIdData", "sessionPayload"].contains(key) {
                return "\(key)=\(String(describing: value).shorten())"
            } else {
                return "\(key)=\(value)"
            }
        }.joined(separator: ", ")
        return "EliteFlowContext(\(entries))"
    }
}

private enum EliteFlowContextKeys {
    fileprivate static let options = EliteFlowContextKey<WebBridgeOperationOptions>("options")
    fileprivate static let eventsWrappers = EliteFlowContextKey<[any WebBridgeOperationEventWrapper]>("eventsWrappers")
}

extension EliteFlowContext {
    /// The WebView display options configured for this context, if any.
    ///
    /// When no options are configured, the flow uses server configuration and SDK defaults.
    internal var options: WebBridgeOperationOptions? {
        self[EliteFlowContextKeys.options]
    }

    internal var eventsWrappers: [any WebBridgeOperationEventWrapper] {
        self[EliteFlowContextKeys.eventsWrappers] ?? []
    }
}

extension EliteFlowContext.Builder {
    /// The WebView display/content options configured for this context.
    ///
    /// Values not set on the options value fall back to server configuration or SDK defaults.
    internal var options: WebBridgeOperationOptions? {
        get { self[EliteFlowContextKeys.options] }
        set { self[EliteFlowContextKeys.options] = newValue }
    }

    /// Configures WebView display/content options through ``EliteFlowOptionsBuilder``.
    ///
    /// Calling this function replaces any options previously configured on this builder. Values not set in `configure`
    /// fall back to server configuration or SDK defaults.
    public mutating func options(_ configure: (EliteFlowOptionsBuilder) -> Void) {
        let builder = EliteFlowOptionsBuilder()
        configure(builder)
        options = builder.build()
    }

    /// Configures hosted-page event handlers for the Elite flow.
    ///
    /// Calling this function replaces any handlers previously configured on this builder.
    public mutating func events(_ configure: (EliteFlowEventBuilder) -> Void) {
        resetEvents()
        let eventBuilder = EliteFlowEventBuilder()
        configure(eventBuilder)
        eventBuilder.build().forEach { wrapper in
            addEvent(wrapper)
        }
    }
}

/// Builder for SDK-managed WebView options used by the Elite flow.
///
/// Configure this builder through ``EliteFlowContext/Builder/options(_:)``. Most integrations leave hosted content
/// options unset and only set native container display values such as ``backgroundColor`` when needed. All values are
/// optional; leave a value `nil` to use server configuration or SDK defaults for that field.
public final class EliteFlowOptionsBuilder {
    /// Base URL for the HTML page. Defaults to `nil` and falls back to server configuration.
    ///
    /// The flow must be able to derive an origin from the resolved value. Page URLs are accepted; path, query, and
    /// fragment are ignored for origin matching. Invalid values fail the flow before WebView presentation.
    public var baseUrl: String?

    /// Raw HTML to render in the SDK-managed WebView. Defaults to `nil` and falls back to server configuration or SDK defaults.
    public var html: String?

    /// Custom WebView User-Agent string. Defaults to `nil` and falls back to the SDK User-Agent value.
    public var userAgent: String?

    /// If `true`, the WebView can be inspected with Safari Web Inspector. Defaults to `false`.
    public var webViewIsInspectable: Bool

    /// Background color for the SDK-managed WebView container and safe-area regions. Defaults to white.
    public var backgroundColor: UIColor?

    /// If `true`, limits the SDK-managed WebView to app-bound domains on iOS 14 and later. Defaults to `false`.
    ///
    /// The host app must also declare trusted domains with the `WKAppBoundDomains` Info.plist key. On iOS 13 this
    /// option has no effect.
    public var limitsNavigationsToAppBoundDomains: Bool

    internal init(options: WebBridgeOperationOptions? = nil) {
        self.baseUrl = options?.baseUrl
        self.html = options?.html
        self.userAgent = options?.userAgent
        self.webViewIsInspectable = options?.webViewIsInspectable ?? false
        self.backgroundColor = options?.backgroundColor
        self.limitsNavigationsToAppBoundDomains = options?.limitsNavigationsToAppBoundDomains ?? false
    }

    internal func build() -> WebBridgeOperationOptions {
        WebBridgeOperationOptions(
            baseUrl: baseUrl,
            html: html,
            userAgent: userAgent,
            webViewIsInspectable: webViewIsInspectable,
            backgroundColor: backgroundColor,
            limitsNavigationsToAppBoundDomains: limitsNavigationsToAppBoundDomains
        )
    }
}

/// Builder for defining event handlers in the OwnID Elite flow.
///
/// All handlers run on the main actor. If a handler is set more than once for the same event, the last handler is used.
/// Hosted `onFinish`, `onNativeAction`, `onError`, and `onClose` events are terminal after the configured handler
/// returns successfully.
public struct EliteFlowEventBuilder {
    private final class Storage {
        var onNativeAction: OnNativeActionWrapper?
        var onFinish: OnFinishWrapper?
        var onError: OnErrorWrapper?
        var onClose: OnCloseWrapper?
    }

    private let storage: Storage

    fileprivate init() {
        self.storage = Storage()
    }

    fileprivate func build() -> [any WebBridgeOperationEventWrapper] {
        var wrappers: [any WebBridgeOperationEventWrapper] = []
        if let onNativeAction = storage.onNativeAction { wrappers.append(onNativeAction) }
        if let onFinish = storage.onFinish { wrappers.append(onFinish) }
        if let onError = storage.onError { wrappers.append(onError) }
        if let onClose = storage.onClose { wrappers.append(onClose) }
        return wrappers
    }

    /// Sets the handler for the `onNativeAction` event.
    ///
    /// Triggered when the hosted flow requires app-owned native handling. This is a terminal event; the WebView closes
    /// and the flow completes successfully after the handler returns. The SDK does not create an app session from this
    /// event.
    ///
    /// - Parameter handler: Receives the `loginID`, optional `ownIdData`, and optional `accessToken` emitted by the
    ///   hosted page.
    public func onNativeAction(
        _ handler: @MainActor @escaping (_ loginID: String, _ ownIdData: String?, _ accessToken: AccessToken?) async -> Void
    ) {
        storage.onNativeAction = OnNativeActionWrapper(onNativeAction: handler)
    }

    /// Sets the handler for the `onFinish` event.
    ///
    /// Triggered when the hosted authentication flow completes successfully. This is a terminal event; the WebView
    /// closes and the flow completes successfully after the handler returns. Use the optional access token at the app
    /// authentication boundary if your integration creates an app session from this outcome.
    ///
    /// - Parameter handler: Receives the `loginID`, `authMethod`, and optional `accessToken` emitted by the hosted page.
    public func onFinish(
        _ handler: @MainActor @escaping (_ loginID: String, _ authMethod: AuthMethod, _ accessToken: AccessToken?) async -> Void
    ) {
        storage.onFinish = OnFinishWrapper(onFinish: handler)
    }

    /// Sets the handler for the `onError` event.
    ///
    /// Triggered when the hosted flow reports an application-level error. This is a terminal event; the WebView closes
    /// and the flow completes successfully after the handler returns. Treat the optional string as display or diagnostic
    /// context from the hosted page, not as an SDK failure payload.
    ///
    /// - Parameter handler: Receives an optional string containing error details.
    public func onError(_ handler: @MainActor @escaping (_ error: String?) async -> Void) {
        storage.onError = OnErrorWrapper(onError: handler)
    }

    /// Sets the handler for the `onClose` event.
    ///
    /// Triggered when the hosted flow reports a close event. This is a terminal event; the WebView closes and the flow
    /// completes successfully after the handler returns. Native user-close controls and controller cancellation
    /// complete the flow with cancellation instead.
    public func onClose(_ handler: @MainActor @escaping () async -> Void) {
        storage.onClose = OnCloseWrapper(onClose: handler)
    }
}
