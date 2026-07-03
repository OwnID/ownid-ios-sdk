import Foundation

/// Thread-safe bridge-scoped plugin registry.
///
/// This registry owns concrete plugin instances for one ``WebBridge``. Initial plugins, app-added plugins, and
/// removals are keyed by ``WebBridgePluginKey``. Replacing an existing key keeps that key's original injection slot, so
/// attachment order is deterministic even when a built-in plugin is replaced.
///
/// The current plugin list is returned as an attachment-time copy. Later registry mutations do not rewrite a previously
/// returned copy.
internal final class WebBridgePluginRegistryImpl: WebBridgePluginRegistry, @unchecked Sendable {
    private let lock = NSLock()
    private var plugins: [any WebBridgePlugin]

    internal init(initialPlugins: [any WebBridgePlugin]) {
        self.plugins = []
        for plugin in initialPlugins {
            if let existingIndex = self.plugins.firstIndex(where: { $0.key == plugin.key }) {
                self.plugins[existingIndex] = plugin
            } else {
                self.plugins.append(plugin)
            }
        }
    }

    internal func add(plugin: any WebBridgePlugin) {
        lock.withLock {
            if let existingIndex = plugins.firstIndex(where: { $0.key == plugin.key }) {
                plugins[existingIndex] = plugin
            } else {
                plugins.append(plugin)
            }
        }
    }

    internal func remove(key: WebBridgePluginKey) {
        lock.withLock {
            plugins.removeAll { $0.key == key }
        }
    }

    internal func get(key: WebBridgePluginKey) -> (any WebBridgePlugin)? {
        lock.withLock {
            return plugins.first { $0.key == key }
        }
    }

    /// Returns the current plugin instances in injection order as a stable copy for WebBridge attachment.
    internal func snapshot() -> [any WebBridgePlugin] {
        lock.withLock {
            plugins
        }
    }
}
