import Foundation

/// Resolves dependencies visible from one SDK-internal scope.
///
/// Lookup starts in the bound scope and walks parent scopes. When a parent binding is a factory, the factory receives
/// the original requester so child-scope overrides remain visible during nested resolution. Resolver calls are
/// synchronous, do not hop actors, and do not own cancellation for resolved objects or factory-created work.
@_spi(OwnIDInternal) public protocol DIContainerResolver: Sendable {
    /// Scope name used in diagnostic traces and resolution errors.
    var scopeName: String { get }

    /// Returns `true` when the type and its declared dependencies are registered without a declared cycle.
    func canResolve(_ type: Any.Type) -> Bool

    /// Returns missing or cyclic declared dependency traces for the type, or `nil` when none are found.
    func getUnsatisfiedDependencies(for type: Any.Type) -> [String]?

    /// Resolves the dependency for the given type or throws.
    ///
    /// - Throws: ``MissingDependencyError`` if not registered; ``DependencyResolutionError`` on resolution failure.
    func getOrThrow<T: Any & Sendable>(type: T.Type) throws -> T

    /// Resolves the type, or returns `nil` after suppressing missing-dependency and resolution failures.
    func getOrNil<T: Any & Sendable>(type: T.Type) -> T?

    /// Returns matching visible bindings across the scope tree, omitting entries that fail best-effort resolution.
    func getAllInstancesOf(where matchesType: @Sendable (Any.Type) -> Bool) -> [any Sendable]
}

@_spi(OwnIDInternal) extension DIContainerResolver {

    @inlinable
    public func canResolve<T: Any & Sendable>(_ type: T.Type = T.self) -> Bool { canResolve(type) }

    @inlinable
    public func getUnsatisfiedDependencies<T: Any & Sendable>(for type: T.Type = T.self) -> [String]? {
        getUnsatisfiedDependencies(for: type)
    }

    @inlinable
    public func getOrThrow<T: Any & Sendable>(_ type: T.Type = T.self) throws -> T { try getOrThrow(type: type) }

    @inlinable
    public func getOrNil<T: Any & Sendable>(_ type: T.Type = T.self) -> T? { getOrNil(type: type) }
}

/// Registers dependencies into one SDK-internal scope.
///
/// Registrations replace bindings for the same type in this scope only. Child scopes inherit visible parent bindings,
/// while parent and sibling scopes are not mutated. Factory bindings are invoked for each resolution; register an
/// instance when shared identity or lifecycle ownership is required.
@_spi(OwnIDInternal) public protocol DIContainerRegistrar: Sendable {

    /// Creates a child scope with the given name, inheriting this container's registrations.
    @discardableResult
    func createScope(scopeName: String) -> any DIContainer

    /// Registers a pre-built instance for the given type.
    func register<T: Any & Sendable>(_ type: T.Type, instance: T)

    /// Registers a non-memoized factory for the given type with declared dependencies for resolvability checks.
    func registerFactory<T: Any & Sendable>(
        _ type: T.Type,
        dependencies: [Any.Type],
        factory: @escaping @Sendable (any DIContainerResolver) throws -> T
    )

    /// Removes the registration for the given type from this scope.
    func remove<T: Any & Sendable>(_ type: T.Type)
}

@_spi(OwnIDInternal) extension DIContainerRegistrar {

    @inlinable
    public func register<T: Any & Sendable>(_ instance: T) { register(T.self, instance: instance) }

    @inlinable
    public func registerFactory<T: Any & Sendable>(
        dependencies: [Any.Type] = [],
        factory: @escaping @Sendable (any DIContainerResolver) throws -> T
    ) {
        registerFactory(T.self, dependencies: dependencies, factory: factory)
    }

    @inlinable
    public func remove<T: Any & Sendable>(_ type: T.Type) { remove(type) }
}

/// Internal SDK module container that can both resolve and register scoped dependencies.
@_spi(OwnIDInternal) public typealias DIContainer = DIContainerResolver & DIContainerRegistrar
