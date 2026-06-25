import Foundation

/// Bridge-scoped registry of concrete plugins used by a ``WebBridge``.
///
/// Add or remove plugins before ``WebBridge/attach(webView:allowedOriginRules:)`` to control what that
/// bridge instance injects into the page.
///
/// Add distinct plugin instances per bridge. Do not reuse the same plugin instance across multiple
/// ``WebBridgePluginRegistry`` values or bridge instances.
///
/// ``WebBridge/attach(webView:allowedOriginRules:)`` uses a captured copy of the registry at the time of injection.
/// Mutations made later do not affect an already attached bridge instance.
public protocol WebBridgePluginRegistry: Sendable {

    /// Adds `plugin` so it is exposed to the web page via its namespace and actions.
    ///
    /// If another plugin is already present with the same ``WebBridgePlugin/key``, it is replaced.
    /// The `plugin` instance must be owned by this registry only and must not be shared with another bridge.
    ///
    /// Changes affect future captured copies taken from this registry, not the already attached bridge instance.
    func add(plugin: any WebBridgePlugin)

    /// Removes the plugin identified by its ``WebBridgePlugin/key``.
    ///
    /// Changes affect future captured copies taken from this registry, not the already attached bridge instance.
    func remove(key: WebBridgePluginKey)

    /// Returns the registered plugin for `key`, or `nil` if none is registered.
    func get(key: WebBridgePluginKey) -> (any WebBridgePlugin)?

    /// Returns the currently registered plugins in bridge injection order. Replacing a plugin keeps its existing slot.
    func snapshot() -> [any WebBridgePlugin]
}
