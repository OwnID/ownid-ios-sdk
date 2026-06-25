import Foundation
import WebKit

/// Stable identifier for a WebBridge plugin.
///
/// Use this key to work with plugin factories on ``OwnIDWebBridge/defaultPluginFactories`` and with concrete plugins in
/// ``WebBridge/plugins``.
public struct WebBridgePluginKey: Hashable, Sendable, CustomStringConvertible {
    /// JavaScript plugin namespace identifier.
    public let id: String

    /// Canonical string form of the key in the `PLUGIN_ID` format.
    public let key: String

    /// Creates a plugin key from a JavaScript namespace identifier.
    ///
    /// The identifier is normalized to uppercase so keys that differ only by letter case compare equally.
    public init(id: String) {
        precondition(id.contains(where: { !$0.isWhitespace }), "id must not be blank")
        self.id = id.uppercased()
        self.key = self.id
    }

    /// Canonical string representation of this key.
    public var description: String { key }

    public static func == (lhs: WebBridgePluginKey, rhs: WebBridgePluginKey) -> Bool {
        lhs.key == rhs.key
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(key)
    }
}

/// Exposes native SDK functionality to the OwnID Web SDK through a ``WebBridge``.
///
/// Each plugin declares a stable ``key`` and the ``actions`` it advertises for document-start injection. A plugin
/// instance belongs to a single bridge lifecycle, so create a fresh instance for each bridge you configure. The bridge
/// routes allowed main-frame messages to the matching plugin by key. The plugin interprets
/// ``WebBridgePluginMessage/Payload/action`` and returns the ``WebBridgePluginResult`` to send to the JavaScript
/// callback path from the message payload.
public protocol WebBridgePlugin: AnyObject, Sendable {

    /// Stable plugin key used for replacement and lookup inside WebBridge APIs.
    var key: WebBridgePluginKey { get }

    /// Action names advertised to JavaScript for this plugin namespace, for example `["create", "get"]`.
    var actions: [String] { get }

    /// Returns the namespace and actions to inject into JavaScript, or `nil` to skip injection.
    ///
    /// Return `nil` when a plugin should handle messages without contributing document-start injection metadata, or
    /// when the plugin has no configured capability to expose.
    func injectionData() -> (String, [String])?

    /// Handles an incoming bridge message and returns a result to send back to the page.
    ///
    /// Implementations may run off the main actor. They should hop to the main actor only for platform APIs that
    /// require it and should return ``WebBridgePluginResult`` for expected bridge outcomes. Unexpected thrown errors
    /// are converted to bridge error payloads.
    func handle(_ message: WebBridgePluginMessage) async -> WebBridgePluginResult
}

extension WebBridgePlugin {
    /// Default implementation returning ``WebBridgePluginKey/id`` and ``actions`` for JavaScript injection.
    public func injectionData() -> (String, [String])? {
        let actions = actions
        return actions.isEmpty ? nil : (key.id, actions)
    }
}

/// Built-in CONTEXT namespace that forwards the scoped OwnID ``Context`` to the hosted page when available.
internal protocol WebBridgeContextPlugin: WebBridgePlugin {}

extension WebBridgeContextPlugin {
    internal static var KEY: WebBridgePluginKey { WebBridgePluginKey(id: "CONTEXT") }

    internal var key: WebBridgePluginKey { Self.KEY }

    internal var actions: [String] { ["get"] }
}

/// An incoming message from the web page destined for a ``WebBridgePlugin``.
///
/// ``WebBridge`` creates this value only after the payload has been decoded, the callback path has been validated,
/// the message has been limited to the main frame, and the source origin has passed the bridge origin policy.
public struct WebBridgePluginMessage: Sendable {
    /// The source web view.
    public let webView: WKWebView
    /// The origin of the page that sent the message.
    public let sourceOrigin: URL
    /// `true` if the message came from the main frame.
    public let isMainFrame: Bool
    /// Normalized origin rules accepted for this bridge attachment.
    ///
    /// A global wildcard attachment is represented as `["*"]`.
    public let allowedOriginRules: Set<String>
    /// The deserialized message payload.
    public let payload: Payload

    /// Deserialized payload of a bridge message.
    ///
    /// The bridge accepts only dot-separated JavaScript identifier paths for `callbackPath` before evaluating the
    /// callback in the page.
    public struct Payload: Codable, Sendable {
        /// Plugin namespace identifier from JavaScript.
        ///
        /// This value is matched against ``WebBridgePluginKey/id``.
        public let pluginID: String
        /// Action name inside the plugin namespace.
        ///
        /// The bridge passes this through to the plugin; the plugin decides whether the action is supported.
        public let action: String
        /// Dot-separated JavaScript callback path to invoke with the result payload.
        public let callbackPath: String
        /// Optional serialized parameters payload.
        public let params: String?

        /// Creates a bridge message payload.
        ///
        /// - Parameters:
        ///   - pluginID: Plugin namespace identifier from JavaScript.
        ///   - action: Action name inside the plugin namespace.
        ///   - callbackPath: Dot-separated JavaScript callback path to invoke with the result payload.
        ///   - params: Optional serialized parameters payload.
        public init(pluginID: String, action: String, callbackPath: String, params: String? = nil) {
            self.pluginID = pluginID
            self.action = action
            self.callbackPath = callbackPath
            self.params = params
        }

        private enum CodingKeys: String, CodingKey {
            case pluginID = "pluginId"
            case action
            case callbackPath
            case params
        }
    }

    /// Creates a decoded bridge message.
    ///
    /// - Parameters:
    ///   - webView: Source web view.
    ///   - sourceOrigin: Origin of the page that sent the message.
    ///   - isMainFrame: `true` if the message came from the main frame.
    ///   - allowedOriginRules: Origins the bridge was injected with.
    ///   - payload: Deserialized message payload.
    public init(
        webView: WKWebView,
        sourceOrigin: URL,
        isMainFrame: Bool,
        allowedOriginRules: Set<String>,
        payload: Payload
    ) {
        self.webView = webView
        self.sourceOrigin = sourceOrigin
        self.isMainFrame = isMainFrame
        self.allowedOriginRules = allowedOriginRules
        self.payload = payload
    }
}

/// The result sent back to the web page after handling a message.
///
/// A result returns either `success` or `error`. Error payloads are normalized into the bridge failure shape when
/// encoded for JavaScript. Dictionary error payloads without `type` receive `UNKNOWN`; cancellation paths may use
/// `ABORTED`.
public struct WebBridgePluginResult: Codable, Sendable {
    /// Successful result payload.
    ///
    /// `JSONValue.null` is a successful JavaScript `null` result; `nil` means this result has no success payload.
    public let success: JSONValue?
    /// Error payload.
    public let error: JSONValue?

    // nil means no result, JSONValue.null means there is a result just it's null
    private init(success: JSONValue? = nil, error: JSONValue? = nil) {
        self.success = success
        self.error = error
    }

    /// Creates a success result payload.
    ///
    /// - Parameter value: Optional success payload.
    public static func success(_ value: JSONValue?) -> WebBridgePluginResult {
        return WebBridgePluginResult(success: value)
    }

    /// Creates an error result payload.
    ///
    /// - Parameters:
    ///   - message: Error message string.
    ///   - type: Optional bridge error type to include in the encoded payload.
    public static func error(message: String, type: String? = nil) -> WebBridgePluginResult {
        var payload: [String: String] = ["message": message]
        if let type = type, type.isEmpty == false {
            payload["type"] = type
        }
        return WebBridgePluginResult(error: JSONValue(payload))
    }

    /// Serializes this result for callback dispatch to JavaScript.
    public func toResultString(coder: any JSONCoder) -> String {
        do {
            if let success = success {
                return try coder.encodeToString(success)
            } else {
                let baseError: JSONValue =
                    error
                    ?? JSONValue.dictionary([
                        "message": JSONValue("WebBridgePluginResult.error: This is unexpected. Report to OwnID team")
                    ])
                let normalizedError: JSONValue
                switch baseError {
                case .dictionary(var dict):
                    if dict["type"] == nil {
                        dict["type"] = JSONValue("UNKNOWN")
                    }
                    normalizedError = .dictionary(dict)
                default:
                    normalizedError = baseError
                }
                return try coder.encodeToString(["error": normalizedError])
            }
        } catch {
            return
                "{ \"error\": { \"type\" : \"UNKNOWN\", \"message\" : \"WebBridgePluginResult.error: This is unexpected. Report to OwnID team\"} }"
        }
    }
}
