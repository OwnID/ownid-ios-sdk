import Foundation

/// Process-wide root container for OwnID SDK modules.
///
/// This is an internal SDK module contract, not a public app integration contract. The root owns process-wide
/// capabilities and named instance lifecycles. A named instance is the replacement and destroy boundary for its
/// configuration, scoped dependencies, namespace wrapper, and instance-owned work.
///
/// Previously returned containers and namespace wrappers are bound to the lifecycle that produced them. Modules that
/// need to survive replacement or destruction should observe ``OwnID/getInstanceContainerStream(_:)`` and rebind to the
/// current container. Lifecycle mutations are serialized, and the stream yields the current snapshot followed by create,
/// replace, and destroy updates for the named instance.
internal final class OwnIDRootDIContainer: DIContainerImpl, @unchecked Sendable {
    internal static let shared = OwnIDRootDIContainer()

    private final class InstanceEntry {
        var container: (any DIContainer)?
        var namespace: (any OwnIDFullInstance)?
        var continuations: [UUID: AsyncStream<(any DIContainer)?>.Continuation] = [:]

        init(container: (any DIContainer)? = nil, namespace: (any OwnIDFullInstance)? = nil) {
            self.container = container
            self.namespace = namespace
        }
    }

    private let instanceLock = NSRecursiveLock()
    private let lifecycleLock = NSRecursiveLock()
    private var rootDefaultsInjected = false
    nonisolated(unsafe) private var instances: [InstanceName: InstanceEntry] = [:]

    private init() {
        super.init(scopeName: "ROOT")

        register(  //TODO Multi instance logging issue
            OwnIDLogRouter.self,
            instance: OwnIDLogRouter(ownIDLoggerProvider: { [weak self] in self?.getOrNil(type: (any OwnIDLogger).self) }) { [weak self] in
                guard let self else { return [] }
                let containers: [any DIContainer] = instanceLock.withLock { instances.values.compactMap(\.container) }
                return containers.compactMap { container in container.getOrNil(type: ServerLogger.self) }
            }
        )

        register((any JSONCoder).self, instance: JSONCoderImpl())
    }

    internal func injectRootDefaults() {
        instanceLock.withLock {
            let rootLogRouter = getOrNil(type: OwnIDLogRouter.self)

            if rootDefaultsInjected {
                rootLogRouter?.logI(source: Self.self, prefix: "injectRootDefaults", message: "Already injected. Ignoring.")
                return
            }

            struct LoggerAdapter: DIContainerLogger {
                let router: OwnIDLogRouter?
                let enableTrace: Bool

                func trace(container: any DIContainerResolver, tag: String, msg: String?) {
                    guard enableTrace, let router else { return }
                    if shouldSuppress(message: msg) { return }
                    router.logV(source: container, prefix: tag, message: msg)
                }

                func error(container: any DIContainerResolver, tag: String, msg: String?, cause: (any Error)?) {
                    guard let router else { return }
                    if shouldSuppress(message: msg) { return }
                    router.logI(source: container, prefix: tag, message: msg, cause: cause)
                }

                private func shouldSuppress(message: String?) -> Bool {
                    guard let message, !message.isEmpty else { return false }
                    return message.contains("OwnIDLogRouter") || message.contains("OwnIDLogger") || message.contains("ServerLogger")
                }
            }

            #if DEBUG
                let isDebugBuild = true
            #else
                let isDebugBuild = false
            #endif

            setLogger(LoggerAdapter(router: rootLogRouter, enableTrace: isDebugBuild))

            register(UIContextProviderImpl() as any UIContextProvider)

            register(LocalInfoImpl() as any LocalInfo)

            register(LanguageTagsProviderImpl(logger: rootLogRouter) as any LanguageTagsProvider)

            rootDefaultsInjected = true
        }
    }

    @discardableResult
    internal func initializeInstanceContainer(
        _ instanceName: InstanceName = .default,
        configuration: any OwnIDConfiguration
    ) -> any DIContainer {
        lifecycleLock.withLock {
            let instanceScope = createScope(scopeName: instanceName.value)
            instanceScope.injectInstanceDefaults(instanceName: instanceName, configuration: configuration)
            let namespace = instanceScope.instanceNamespace

            let (previousInstance, continuations): (InstanceEntry?, [AsyncStream<(any DIContainer)?>.Continuation]) = instanceLock.withLock
            {
                let entry = getOrCreateInstanceEntry(instanceName)
                let previous = InstanceEntry(container: entry.container, namespace: entry.namespace)
                entry.container = instanceScope
                entry.namespace = namespace
                let continuations = Array(entry.continuations.values)
                return (previous, continuations)
            }

            destroyInstanceSideEffects(previousInstance?.container, instanceName: instanceName)

            let logRouter = instanceScope.getOrNil(type: OwnIDLogRouter.self)
            if !instanceScope.canResolve((any OperationUIContainer).self) {
                logRouter?.logI(
                    source: Self.self,
                    prefix: "initializeInstanceContainer",
                    message: "No UI module injected. OperationUIContainer missing"
                )
            }

            logRouter?.logD(source: Self.self, prefix: "initializeInstanceContainer", message: "Instance created: \(instanceName.value)")
            continuations.forEach { $0.yield(instanceScope) }

            return instanceScope
        }
    }

    internal func getInstanceContainer(_ instanceName: InstanceName = .default) -> (any DIContainer)? {
        instanceLock.withLock {
            instances[instanceName]?.container
        }
    }

    internal func getInstanceNamespace(_ instanceName: InstanceName = .default) -> (any OwnIDFullInstance)? {
        instanceLock.withLock {
            instances[instanceName]?.namespace
        }
    }

    internal func getInstanceContainerStream(_ instanceName: InstanceName = .default) -> AsyncStream<(any DIContainer)?> {
        AsyncStream { continuation in
            let id = UUID()

            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                _ = self.instanceLock.withLock {
                    self.instances[instanceName]?.continuations.removeValue(forKey: id)
                }
            }

            let currentContainer = instanceLock.withLock {
                let entry = getOrCreateInstanceEntry(instanceName)
                entry.continuations[id] = continuation
                return entry.container
            }

            continuation.yield(currentContainer)
        }
    }

    internal func destroyInstanceContainer(_ instanceName: InstanceName = .default) {
        lifecycleLock.withLock {
            let (removedEntry, continuations): (InstanceEntry?, [AsyncStream<(any DIContainer)?>.Continuation]) = instanceLock.withLock {
                guard let entry = instances[instanceName] else { return (nil, []) }
                guard entry.container != nil else { return (nil, []) }
                let removedEntry = InstanceEntry(container: entry.container, namespace: entry.namespace)
                entry.container = nil
                entry.namespace = nil
                let continuations = Array(entry.continuations.values)
                return (removedEntry, continuations)
            }
            destroyInstanceSideEffects(removedEntry?.container, instanceName: instanceName)
            continuations.forEach { $0.yield(nil) }
        }
    }

    private func getOrCreateInstanceEntry(_ instanceName: InstanceName) -> InstanceEntry {
        if let entry = instances[instanceName] {
            return entry
        }

        let entry = InstanceEntry()
        instances[instanceName] = entry
        return entry
    }

    private func destroyInstanceSideEffects(_ instance: (any DIContainer)?, instanceName: InstanceName) {
        guard let instance else { return }

        if let token = instance.getOrNil(type: ShutdownToken.self) {
            token.cancel()
        }

        if let logger = instance.getOrNil(type: OwnIDLogRouter.self) {
            logger.logD(source: Self.self, prefix: "destroyInstanceContainer", message: "Instance destroyed: \(instanceName.value)")
        }
    }
}
