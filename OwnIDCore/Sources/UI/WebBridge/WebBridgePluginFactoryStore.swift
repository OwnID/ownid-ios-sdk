import Foundation

/// Mutable set of default plugin factories for future ``WebBridge`` instances.
///
/// This store belongs to an ``OwnIDWebBridge`` namespace. Factories are managed by ``WebBridgePluginKey``, and
/// registering the same key again replaces the previous factory for that plugin slot.
///
/// Changes are namespace-scoped. They affect only bridges created from that namespace after the update and do not
/// modify bridges that already exist.
public protocol WebBridgePluginFactoryStore: AnyObject, Sendable {
    /// Registers a plugin factory for `key`.
    ///
    /// The `instantiate` block should create a fresh plugin instance each time a bridge is created. If another factory
    /// is already registered for the same `key`, it is replaced in the same factory slot.
    ///
    /// If `instantiate` throws, or if the created plugin reports a different ``WebBridgePlugin/key``, bridge creation
    /// logs a warning and skips that plugin instead of failing the whole bridge.
    func register(key: WebBridgePluginKey, instantiate: @escaping () throws -> any WebBridgePlugin)

    /// Unregisters the factory registered for `key`, if present.
    func unregister(key: WebBridgePluginKey)

    /// Returns `true` if a factory is registered for `key`.
    func has(key: WebBridgePluginKey) -> Bool
}
