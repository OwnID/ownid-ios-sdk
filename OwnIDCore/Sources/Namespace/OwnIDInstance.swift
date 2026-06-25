import Foundation

/// Configured OwnID SDK instance.
///
/// Obtain an instance with ``OwnID/instance(instanceName:)`` after initialization and use it as the entry point to
/// scoped OwnID namespaces such as flows, headless integrations, and WebBridge.
///
/// Instance handles are bound to the SDK scope they were obtained from.
/// After ``OwnID/destroy(instanceName:)`` or same-name reinitialization, previously returned handles and namespaces
/// derived from them are invalid and should be reacquired from ``OwnID/instance(instanceName:)``.
///
/// ``withContext(_:_:)`` and ``withProviders(_:_:)`` return ``OwnIDInstance`` views bound to child scopes and leave
/// this instance's current scope unchanged. ``setContext(_:)``, ``clearContext()``, and ``setProviders(_:)`` update
/// this instance's current scope in place and return this instance view. ``withProviders(_:_:)`` and
/// ``setProviders(_:)`` return the current instance unchanged when the registrar does not register providers.
public protocol OwnIDInstance: Sendable, OwnIDNamespace, ContextOverride, ProvidersOverride {
    var configuration: any OwnIDConfiguration { get }

    var localInfo: any LocalInfo { get }

    /// Authentication flows.
    var flows: OwnIDFlows { get }

    /// UI-less authentication APIs, operations, and flows.
    var headless: OwnIDHeadless { get }

    /// WebBridge integration.
    ///
    /// Use this namespace to configure ``OwnIDWebBridge/defaultPluginFactories`` for future bridges in the current
    /// scope and to create fresh ``WebBridge`` instances for web view sessions.
    var webBridge: OwnIDWebBridge { get }
}

/// Full instance namespace visible only to SDK modules.
///
/// This is an internal SDK module contract, not a public app integration contract. It exposes Core-owned direct API and
/// operation namespaces to modules that intentionally import OwnID internals.
@_spi(OwnIDInternal) public protocol OwnIDFullInstance: OwnIDInstance {
    var api: OwnIDAPI { get }

    var ops: OwnIDOperation { get }
}

internal struct OwnIDInstanceImpl: OwnIDFullInstance {
    internal let container: any DIContainer

    let api: OwnIDAPI
    let ops: OwnIDOperation
    let flows: OwnIDFlows
    let headless: OwnIDHeadless
    let webBridge: OwnIDWebBridge

    init(container: any DIContainer) {
        self.container = container
        self.api = container.apiNamespace
        self.ops = container.opsNamespace
        self.flows = container.flowsNamespace
        self.headless = container.headlessNamespace
        self.webBridge = container.webBridgeNamespace
    }

    var configuration: any OwnIDConfiguration {
        try! container.getOrThrow(type: (any OwnIDConfiguration).self)
    }

    var localInfo: any LocalInfo {
        try! container.getOrThrow(type: (any LocalInfo).self)
    }
}

extension OwnIDInstanceImpl: OwnIDNamespaceSupport, ContextOverrideSupport, ProvidersOverrideSupport {}

extension OwnIDInstanceImpl {
    internal func rebind(container: any DIContainer) -> OwnIDInstanceImpl {
        OwnIDInstanceImpl(container: container)
    }
}

extension DIContainerRegistrar where Self: DIContainerResolver {
    internal var instanceNamespace: any OwnIDFullInstance {
        OwnIDInstanceImpl(container: self)
    }
}
