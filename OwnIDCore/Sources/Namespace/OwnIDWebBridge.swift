import Foundation

/// OwnID WebBridge namespace for web view integrations.
///
/// Use this namespace to scope future bridge instances with ``withContext(_:_:)`` or ``withProviders(_:_:)``,
/// customize ``defaultPluginFactories``, and create a new ``WebBridge`` for each WKWebView session. Scope changes and
/// default factory edits affect bridges created from the returned namespace after the change; existing bridge instances
/// are not updated.
///
/// Namespace handles are captured views bound to the SDK scope they were obtained from.
/// After ``OwnID/destroy(instanceName:)`` or same-name reinitialization, previously returned namespace handles are
/// invalid and should be reacquired from ``OwnID/webBridge`` or the current ``OwnIDInstance``.
///
/// Access this API via ``OwnID/webBridge`` or ``OwnIDInstance/webBridge``.
public final class OwnIDWebBridge: @unchecked Sendable, OwnIDNamespace {
    internal let container: any DIContainer
    internal let pluginFactoryStore: WebBridgePluginFactoryStoreImpl

    internal init(container: any DIContainer, pluginFactoryStore: WebBridgePluginFactoryStoreImpl) {
        self.container = container
        self.pluginFactoryStore = pluginFactoryStore
    }

    /// Creates a new ``WebBridge`` using the current namespace configuration.
    ///
    /// The returned bridge starts with fresh plugin instances created from the current ``defaultPluginFactories``.
    /// Definitions that cannot create a plugin are skipped with a warning so the rest of the bridge can still be used.
    ///
    /// You can further adjust the returned bridge through ``WebBridge/plugins`` before calling
    /// ``WebBridge/attach(webView:allowedOriginRules:)``, for example to add or replace plugins for that specific
    /// bridge instance.
    ///
    /// - Returns: A new bridge instance for a single WKWebView session.
    public func create() -> any WebBridge {
        WebBridgeImpl.create(
            resolver: container,
            initialPlugins: pluginFactoryStore.instantiateAll(resolver: container)
        )
    }

    /// Default plugin factories used for future ``WebBridge`` instances created by this namespace.
    ///
    /// The default namespace starts with the built-in SDK plugins. Update this store to add, replace, or unregister
    /// default plugins for bridges created from this namespace. The store keeps factory functions and invokes them
    /// once for each new bridge so every bridge receives fresh plugin instances.
    ///
    /// Scoped namespace views receive a copy of the current store, so later edits are isolated to that namespace
    /// handle. These changes do not affect bridges that have already been created.
    public var defaultPluginFactories: any WebBridgePluginFactoryStore {
        pluginFactoryStore
    }

}

extension OwnIDWebBridge: OwnIDNamespaceSupport {
    internal func rebind(container: any DIContainer) -> OwnIDWebBridge {
        OwnIDWebBridge(container: container, pluginFactoryStore: pluginFactoryStore.copyStore())
    }
}

extension DIContainerRegistrar where Self: DIContainerResolver {
    internal var webBridgeNamespace: OwnIDWebBridge {
        let pluginFactoryStore = (try! getOrThrow(type: WebBridgePluginFactoryStoreImpl.self).copyStore())
        return OwnIDWebBridge(container: self, pluginFactoryStore: pluginFactoryStore)
    }
}
