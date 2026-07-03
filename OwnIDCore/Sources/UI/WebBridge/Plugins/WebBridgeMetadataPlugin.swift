import Foundation

/// Internal METADATA WebBridge plugin that forwards SDK correlation metadata.
///
/// The plugin exposes the `METADATA` key with the `get` action. Plugin ID and action matching are case-insensitive.
/// `get` ignores params and returns `{ "correlationId": ... }` from ``LocalInfo``. Wrong plugin IDs and unknown actions
/// are returned as bridge error payloads. The plugin depends on ``LocalInfo`` only for the returned metadata and does
/// not expose broader environment, diagnostics, repository, or provider state to the hosted page.
internal actor WebBridgeMetadataPlugin: WebBridgePlugin {
    internal static let KEY = WebBridgePluginKey(id: "METADATA")

    nonisolated var key: WebBridgePluginKey { Self.KEY }
    nonisolated let actions: [String] = ["get"]

    private let localInfo: any LocalInfo
    private let coder: any JSONCoder

    init(localInfo: any LocalInfo, coder: any JSONCoder) {
        self.localInfo = localInfo
        self.coder = coder
    }

    nonisolated func handle(_ message: WebBridgePluginMessage) async -> WebBridgePluginResult {
        await handleIsolated(message)
    }

    private func handleIsolated(_ message: WebBridgePluginMessage) async -> WebBridgePluginResult {
        guard key.id.caseInsensitiveCompare(message.payload.pluginID) == .orderedSame else {
            return WebBridgePluginResult.error(message: "WebBridgeMetadataPlugin: Wrong plugin ID: \(message.payload.pluginID)")
        }

        switch message.payload.action.uppercased() {
        case "GET": return WebBridgePluginResult.success(JSONValue(["correlationId": localInfo.correlationId]))
        default: return WebBridgePluginResult.error(message: "WebBridgeMetadataPlugin: Unknown action: \(message.payload.action)")
        }
    }
}

extension WebBridgeMetadataPlugin {
    internal static func create(resolver: any DIContainerResolver) throws -> WebBridgeMetadataPlugin {
        WebBridgeMetadataPlugin(
            localInfo: try resolver.getOrThrow(type: (any LocalInfo).self),
            coder: try resolver.getOrThrow(type: (any JSONCoder).self)
        )
    }
}
