import Foundation

internal protocol DIContainerLogger: Sendable {
    var enableTrace: Bool { get }
    func trace(container: any DIContainerResolver, tag: String, msg: String?)
    func error(container: any DIContainerResolver, tag: String, msg: String?, cause: (any Error)?)
}

/// Internal dependency container for the SDK module graph.
///
/// The cross-module contract is hierarchical scope resolution: child scopes inherit parent bindings, child
/// registrations override only that child subtree, and factories resolve against the original requester so child-scope
/// overrides are honored. The unchecked `Sendable` conformance relies on the locks guarding binding storage, logging,
/// and resolution-cycle state; factories execute synchronously without container-owned caching or cancellation.
@_spi(OwnIDInternal) public class DIContainerImpl: DIContainer, @unchecked Sendable {

    private enum Binding: Sendable {
        case instance(type: Any.Type, value: any Sendable)
        case factory(type: Any.Type, dependencies: [Any.Type], factory: @Sendable (any DIContainerResolver) throws -> any Sendable)

        var registeredType: Any.Type {
            switch self {
            case .instance(let type, _), .factory(let type, _, _): return type
            }
        }

        var dependencies: [Any.Type] {
            switch self {
            case .instance: return []
            case .factory(_, let deps, _): return deps
            }
        }
    }

    private struct ResolutionKey: Equatable {
        let containerID: ObjectIdentifier
        let type: Any.Type
        let scopeName: String
        let typeName: String

        init(container: DIContainerImpl, type: Any.Type) {
            self.containerID = ObjectIdentifier(container)
            self.type = type
            self.scopeName = container.scopeName
            self.typeName = String(describing: type)
        }

        static func == (lhs: ResolutionKey, rhs: ResolutionKey) -> Bool {
            lhs.containerID == rhs.containerID && ObjectIdentifier(lhs.type) == ObjectIdentifier(rhs.type)
        }
    }

    nonisolated(unsafe) private static var resolutionStack: [ResolutionKey] = []
    private static let resolutionLock = NSRecursiveLock()

    public let scopeName: String

    private let parent: (any DIContainer)?
    private var bindings: [ObjectIdentifier: Binding] = [:]
    private let lock = NSLock()
    private var logger: (any DIContainerLogger)?

    internal init(scopeName: String, parent: (any DIContainer)? = nil) {
        self.scopeName = scopeName
        self.parent = parent
    }

    internal func setLogger(_ logger: (any DIContainerLogger)?) {
        lock.lock()
        self.logger = logger
        lock.unlock()
    }

    private func currentLogger() -> (any DIContainerLogger)? {
        lock.lock()
        let value = logger
        lock.unlock()
        return value
    }

    private func binding(for type: Any.Type) -> Binding? {
        let key = ObjectIdentifier(type)
        lock.lock()
        let value = bindings[key]
        lock.unlock()
        return value
    }

    private func logTrace(tag: String, _ message: @autoclosure () -> String) {
        guard let logger = currentLogger(), logger.enableTrace else { return }
        logger.trace(container: self, tag: "\(scopeName):\(tag)", msg: message())
    }

    private func logError(tag: String, msg: String?, cause: (any Error)?) {
        guard let logger = currentLogger() else { return }
        logger.error(container: self, tag: "\(scopeName):\(tag)", msg: msg, cause: cause)
    }

    @discardableResult
    public func createScope(scopeName: String) -> any DIContainer {
        let child = DIContainerImpl(scopeName: scopeName, parent: self)
        child.setLogger(currentLogger())
        return child
    }

    public func register<T: Any & Sendable>(_ type: T.Type, instance: T) {
        let key = ObjectIdentifier(type)
        var overwritten = false

        lock.lock()
        if bindings[key] != nil { overwritten = true }
        bindings[key] = .instance(type: type, value: instance)
        lock.unlock()

        logTrace(tag: "register", "For \(String(describing: type)) (overwritten=\(overwritten))")
    }

    public func registerFactory<T: Any & Sendable>(
        _ type: T.Type,
        dependencies: [Any.Type],
        factory: @escaping @Sendable (any DIContainerResolver) throws -> T
    ) {
        let key = ObjectIdentifier(type)
        var overwritten = false

        lock.lock()
        if bindings[key] != nil { overwritten = true }
        bindings[key] = .factory(type: type, dependencies: dependencies, factory: { resolver in try factory(resolver) })
        lock.unlock()

        let depsDescription = dependencies.map { String(describing: $0) }.joined(separator: ", ")
        logTrace(tag: "registerFactory", "For \(String(describing: type)), deps=\(depsDescription) (overwritten=\(overwritten))")
    }

    public func remove<T: Any & Sendable>(_ type: T.Type) {
        let key = ObjectIdentifier(type)
        var removed: T?

        lock.lock()
        if let entry = bindings.removeValue(forKey: key) {
            if case .instance(_, let value) = entry {
                removed = value as? T
            }
        }
        lock.unlock()

        logTrace(tag: "remove", "For \(String(describing: type)), removed=\(removed != nil)")
    }

    public func canResolve(_ type: Any.Type) -> Bool {
        getUnsatisfiedDependencies(for: type) == nil
    }

    public func getUnsatisfiedDependencies(for type: Any.Type) -> [String]? {
        logTrace(tag: "getUnsatisfiedDependencies", "Checking \(String(describing: type))")

        var traces = Set<String>()
        collectUnsatisfiedTraces(type, path: [], traces: &traces, requester: self)
        return traces.isEmpty ? nil : Array(traces)
    }

    public func getOrThrow<T: Any & Sendable>(type: T.Type) throws -> T {
        try getOrThrow(type: type, logMissing: true, requester: self)
    }

    public func getOrNil<T: Any & Sendable>(type: T.Type) -> T? {
        do {
            return try getOrThrow(type: type, logMissing: false, requester: self)
        } catch {
            return nil
        }
    }

    public func getAllInstancesOf(where matchesType: @Sendable (Any.Type) -> Bool) -> [any Sendable] {
        logTrace(tag: "getAllInstancesOf", "Collecting instances")

        var result: [any Sendable] = []
        var seenTypes = Set<ObjectIdentifier>()

        func collect(from container: (any DIContainer)?, requester: DIContainerImpl) {
            guard let container else { return }
            guard let impl = container as? DIContainerImpl else { return }

            let localBindings: [Binding]
            impl.lock.lock()
            localBindings = Array(impl.bindings.values)
            impl.lock.unlock()

            for binding in localBindings {
                let registeredType = binding.registeredType

                guard matchesType(registeredType) else { continue }

                let typeID = ObjectIdentifier(registeredType)
                if seenTypes.contains(typeID) { continue }

                let anyInstance: (any Sendable)?

                do {
                    switch binding {
                    case .instance(_, let value): anyInstance = value
                    case .factory(_, _, let factory): anyInstance = try factory(requester)
                    }
                } catch {
                    logError(
                        tag: "getAllInstancesOf",
                        msg: "Failed to instantiate \(String(describing: registeredType))",
                        cause: error
                    )
                    seenTypes.insert(typeID)
                    continue
                }

                if let anyInstance { result.append(anyInstance) }
                seenTypes.insert(typeID)
            }

            collect(from: impl.parent, requester: requester)
        }

        collect(from: self, requester: self)

        logTrace(tag: "getAllInstancesOf", "Found \(result.count) instance(s)")
        return result
    }

    private func getOrThrow<T: Any & Sendable>(type: T.Type, logMissing: Bool, requester: DIContainerImpl) throws -> T {
        let typeName = String(describing: type)

        Self.resolutionLock.lock()
        let key = ResolutionKey(container: requester, type: type)

        if let start = Self.resolutionStack.firstIndex(of: key) {
            let cyclePath = (Array(Self.resolutionStack[start...]) + [key])
                .map { "\($0.scopeName):\($0.typeName)" }
                .joined(separator: " -> ")
            let entry = Self.resolutionStack.first?.typeName ?? "Direct:get(\(typeName))"
            let causeDescription = "Dependency cycle detected: \(cyclePath)"
            let cause = NSError(domain: "DIContainerImpl", code: 1, userInfo: [NSLocalizedDescriptionKey: causeDescription])

            logError(tag: "getOrThrow", msg: "Cycle while resolving \(typeName)", cause: cause)

            let error = DependencyResolutionError(dependencyName: typeName, scopeName: scopeName, entryPoint: entry, cause: cause)
            Self.resolutionLock.unlock()
            throw error
        }

        Self.resolutionStack.append(key)
        let depth = Self.resolutionStack.count - 1

        defer {
            _ = Self.resolutionStack.popLast()
            if Self.resolutionStack.isEmpty {
                Self.resolutionStack.removeAll(keepingCapacity: false)
            }
            Self.resolutionLock.unlock()
        }

        do {
            guard let anyValue = try resolveInstance(type: type, logMissing: logMissing, requester: requester) else {
                let entry = Self.resolutionStack.first?.typeName ?? "Direct:get(\(typeName))"
                throw MissingDependencyError(dependencyName: typeName, scopeName: requester.scopeName, entryPoint: entry)
            }

            let typed = anyValue as! T
            logTrace(tag: "getOrThrow", "Resolved \(typeName) depth=\(depth)")
            return typed
        } catch let missing as MissingDependencyError {
            if logMissing {
                logError(tag: "getOrThrow", msg: "Missing dependency \(typeName) (depth=\(depth))", cause: missing)
            }
            throw missing
        } catch let resolution as DependencyResolutionError {
            logError(tag: "getOrThrow", msg: "Resolution failure for \(typeName) (depth=\(depth))", cause: resolution)
            throw resolution
        } catch {
            let entry = Self.resolutionStack.first?.typeName ?? "Direct:get(\(typeName))"
            let wrapped = DependencyResolutionError(
                dependencyName: typeName,
                scopeName: requester.scopeName,
                entryPoint: entry,
                cause: error
            )
            logError(tag: "getOrThrow", msg: "Unexpected error resolving \(typeName) (depth=\(depth))", cause: wrapped)
            throw wrapped
        }
    }

    private func resolveInstance<T: Any & Sendable>(type: T.Type, logMissing: Bool, requester: DIContainerImpl) throws -> (any Sendable)? {
        let localBinding = binding(for: type)

        if let binding = localBinding {
            return try resolveLocalBinding(type: type, binding: binding, requester: requester)
        }

        guard let parentImpl = parent as? DIContainerImpl else { return nil }
        return try parentImpl.resolveInstance(type: type, logMissing: logMissing, requester: requester)
    }

    private func resolveLocalBinding<T: Any & Sendable>(type: T.Type, binding: Binding, requester: DIContainerImpl)
        throws -> (any Sendable)?
    {
        switch binding {
        case .instance(_, let value): return value
        case .factory(_, _, let factory): return try factory(requester)
        }
    }

    private func collectUnsatisfiedTraces(_ type: Any.Type, path: [Any.Type], traces: inout Set<String>, requester: DIContainerImpl) {
        if pathContains(path, type: type) {
            traces.insert(formatTrace(path + [type], issue: "cyclic"))
            return
        }

        guard let binding = findBindingInChain(requester: requester, type: type) else {
            traces.insert(formatTrace(path + [type], issue: "missing"))
            return
        }

        let deps = binding.dependencies
        if deps.isEmpty { return }

        var nextPath = path
        nextPath.append(type)
        for depType in deps {
            collectUnsatisfiedTraces(depType, path: nextPath, traces: &traces, requester: requester)
        }
    }

    private func pathContains(_ path: [Any.Type], type: Any.Type) -> Bool {
        let targetID = ObjectIdentifier(type)
        return path.contains { ObjectIdentifier($0) == targetID }
    }

    private func formatTrace(_ path: [Any.Type], issue: String) -> String {
        let labels = path.enumerated().map { index, entryType -> String in
            let name = String(reflecting: entryType)
            return index == 0 ? "\(scopeName):\(name)" : name
        }
        return "\(labels.joined(separator: " -> ")) [\(issue)]"
    }

    private func findBindingInChain(requester: DIContainerImpl, type: Any.Type) -> Binding? {
        var current: DIContainerImpl? = requester
        while let impl = current {
            if let localBinding = impl.binding(for: type) { return localBinding }
            current = impl.parent as? DIContainerImpl
        }
        return nil
    }
}
