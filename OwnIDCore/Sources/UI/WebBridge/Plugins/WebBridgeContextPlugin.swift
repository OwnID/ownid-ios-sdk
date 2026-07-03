import Foundation

/// Internal CONTEXT WebBridge plugin backed by the scoped ``Context`` captured when the bridge is created.
///
/// The plugin exposes the `CONTEXT` key with the `get` action only when a scoped context is available. Plugin ID and
/// action matching are case-insensitive. `get` ignores params and returns the WebBridge context payload:
/// `authz.loginId` for raw or typed login ID authz, `authz.accessToken` for access-token authz, and
/// `accountDisplayName` when present. Wrong plugin IDs, unknown actions, and missing context are returned as bridge
/// error payloads. The plugin depends only on the optional scoped ``Context``; it does not read or write storage, app
/// configuration, or provider capabilities.
internal actor WebBridgeContextPluginImpl: WebBridgeContextPlugin {
    nonisolated var key: WebBridgePluginKey { Self.KEY }
    nonisolated let actions: [String] = ["get"]

    private let context: Context?

    init(context: Context?) {
        self.context = context
    }

    nonisolated func injectionData() -> (String, [String])? {
        guard context != nil else { return nil }
        return (key.id, actions)
    }

    nonisolated func handle(_ message: WebBridgePluginMessage) async -> WebBridgePluginResult {
        await handleIsolated(message)
    }

    private func handleIsolated(_ message: WebBridgePluginMessage) async -> WebBridgePluginResult {
        guard key.id.caseInsensitiveCompare(message.payload.pluginID) == .orderedSame else {
            return WebBridgePluginResult.error(message: "WebBridgeContextPlugin: Wrong plugin ID: \(message.payload.pluginID)")
        }

        switch message.payload.action.uppercased() {
        case "GET":
            guard let context else {
                return WebBridgePluginResult.error(message: "WebBridgeContextPlugin: Context is unavailable")
            }
            return WebBridgePluginResult.success(context.toWebBridgePayload())
        default: return WebBridgePluginResult.error(message: "WebBridgeContextPlugin: Unknown action: \(message.payload.action)")
        }
    }
}

extension WebBridgeContextPluginImpl {
    internal static func create(resolver: any DIContainerResolver) throws -> WebBridgeContextPluginImpl {
        WebBridgeContextPluginImpl(
            context: resolver.getOrNil(type: Context.self)
        )
    }
}
