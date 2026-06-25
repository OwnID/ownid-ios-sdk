import Foundation

/// Mutable factory registry for plugins installed into future WebBridge instances.
///
/// This namespace-level template preserves replacement order, copies independently for scoped namespace views, and
/// skips failed or mismatched factories when creating plugins for one bridge.
internal final class WebBridgePluginFactoryStoreImpl: WebBridgePluginFactoryStore, @unchecked Sendable {
    private struct Entry {
        let key: WebBridgePluginKey
        let instantiate: (any DIContainerResolver) throws -> any WebBridgePlugin
    }

    private let lock = NSLock()
    private var entries: [Entry]

    private init(entries: [Entry]) {
        self.entries = entries
    }

    internal convenience init() {
        self.init(entries: [])
    }

    internal func register(key: WebBridgePluginKey, instantiate: @escaping () throws -> any WebBridgePlugin) {
        lock.withLock {
            let entry = Entry(key: key, instantiate: { _ in try instantiate() })
            if let existingIndex = entries.firstIndex(where: { $0.key == key }) {
                entries[existingIndex] = entry
            } else {
                entries.append(entry)
            }
        }
    }

    internal func unregister(key: WebBridgePluginKey) {
        lock.withLock {
            entries.removeAll { $0.key == key }
        }
    }

    internal func has(key: WebBridgePluginKey) -> Bool {
        lock.withLock {
            entries.contains { $0.key == key }
        }
    }

    /// Stores an SDK built-in factory for future bridge instances.
    internal func registerBuiltIn(
        key: WebBridgePluginKey,
        instantiate: @escaping (any DIContainerResolver) throws -> any WebBridgePlugin
    ) {
        lock.withLock {
            let entry = Entry(key: key, instantiate: instantiate)
            if let existingIndex = entries.firstIndex(where: { $0.key == key }) {
                entries[existingIndex] = entry
            } else {
                entries.append(entry)
            }
        }
    }

    /// Creates concrete plugins for one bridge from the current factory template.
    internal func instantiateAll(resolver: any DIContainerResolver) -> [any WebBridgePlugin] {
        let logger = resolver.getOrNil(type: OwnIDLogRouter.self)
        let snapshot = lock.withLock { entries }
        return snapshot.compactMap { entry in
            do {
                let plugin = try entry.instantiate(resolver)
                guard plugin.key == entry.key else {
                    logger?.logW(
                        source: self,
                        prefix: "instantiateAll",
                        message:
                            "Skipped WebBridge plugin definition \(entry.key): instantiated plugin key \(plugin.key) does not match definition key \(entry.key)"
                    )
                    return nil
                }
                return plugin
            } catch {
                logger?.logW(
                    source: self,
                    prefix: "instantiateAll",
                    message: "Failed to instantiate WebBridge plugin \(entry.key): \(error.localizedDescription)",
                    cause: error
                )
                return nil
            }
        }
    }

    /// Creates an independent factory template with the same definitions in the same order.
    internal func copyStore() -> WebBridgePluginFactoryStoreImpl {
        lock.withLock {
            WebBridgePluginFactoryStoreImpl(entries: entries)
        }
    }
}
