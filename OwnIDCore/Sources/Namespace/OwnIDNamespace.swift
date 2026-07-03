import Foundation

/// Base contract for OwnID namespace handles that can return scoped views.
///
/// Namespace handles are bound to the SDK scope they were obtained from.
/// After ``OwnID/destroy(instanceName:)`` or same-name reinitialization of the owning instance, reacquire the namespace
/// from ``OwnID`` or the current ``OwnIDInstance``.
///
/// Use ``withContext(_:_:)`` to return the same namespace type bound to a child scope with an OwnID ``Context``
/// containing a login ID, access token, or account display name. Use ``withProviders(_:_:)`` to return the same
/// namespace type bound to a child scope with provider overrides.
///
/// Scoped calls leave the current namespace unchanged. ``withProviders(_:_:)`` returns the current namespace when the
/// provider registrar does not register providers.
public protocol OwnIDNamespace: ContextScope, ProvidersScope {}

/// Contract for namespaces that can return a context-scoped view.
public protocol ContextScope {
    /// Returns this namespace scoped with a ``Context`` built from `block`.
    ///
    /// Use this to create a child scope for a specific login ID, access token, or account display name without changing
    /// the current namespace or owning instance.
    /// The returned namespace stays bound to that child scope.
    ///
    /// OwnID does not handle failures triggered by `block`.
    ///
    /// - Parameters:
    ///   - scopeName: Name for the returned child scope. Defaults to `"Context"`.
    ///   - block: Builder that sets the context for the returned scope.
    /// - Returns: The same namespace type scoped for the returned child scope.
    func withContext(_ scopeName: String, _ block: (inout Context.Builder) -> Void) -> Self
}

extension ContextScope {
    /// Returns this namespace scoped with a ``Context`` built from `block`.
    ///
    /// The returned namespace uses a child scope named `"Context"` while keeping the current scope's providers and
    /// configuration available.
    ///
    /// OwnID does not handle failures triggered by `block`.
    ///
    /// - Parameter block: Builder that sets context values for the returned scope.
    /// - Returns: The same namespace type scoped for the returned child scope.
    public func withContext(_ block: (inout Context.Builder) -> Void) -> Self {
        withContext("Context", block)
    }
}

/// Contract for namespaces that can update ``Context`` in place.
public protocol ContextOverride {
    /// Updates the current scope's ``Context``.
    ///
    /// Unlike ``ContextScope/withContext(_:_:)``, this does not create a child scope.
    ///
    /// Merge semantics:
    /// - Fields assigned in `block` replace existing values in the current scope.
    /// - Fields not assigned in `block` keep their existing values.
    /// - Assigning `nil` clears the field in the resulting context.
    ///
    /// OwnID does not handle failures triggered by `block`.
    ///
    /// - Parameter block: Builder that sets context values for the current scope.
    /// - Returns: The namespace for the updated current scope.
    func setContext(_ block: (inout Context.Builder) -> Void) -> Self

    /// Clears the current scope's ``Context``.
    ///
    /// - Returns: The namespace for the updated current scope.
    func clearContext() -> Self
}

/// Contract for namespaces that can return a provider-scoped view.
public protocol ProvidersScope {
    /// Returns this namespace scoped with providers from `block`.
    ///
    /// Use this to create a child scope with custom provider behavior without changing the current namespace or owning
    /// instance.
    /// The returned namespace stays bound to that child scope.
    ///
    /// If `block` does not register any providers, returns the current namespace unchanged.
    ///
    /// OwnID does not handle failures triggered by `block`.
    ///
    /// - Parameters:
    ///   - scopeName: Name for the returned child scope. Defaults to `"Providers"`.
    ///   - block: Closure that registers providers via ``OwnIDProvidersRegistrar``.
    /// - Returns: The same namespace type scoped for the returned child scope, or the current namespace unchanged when
    ///   empty.
    func withProviders(_ scopeName: String, _ block: (inout OwnIDProvidersRegistrar) -> Void) -> Self
}

extension ProvidersScope {
    /// Returns this namespace scoped with providers from `block`.
    ///
    /// The returned namespace uses a child scope named `"Providers"` while keeping the current scope's context and
    /// configuration available.
    ///
    /// Providers declared in `block` replace providers of the same type only in the returned scope.
    ///
    /// If `block` does not register any providers, returns the current namespace unchanged.
    ///
    /// OwnID does not handle failures triggered by `block`.
    ///
    /// - Parameter block: Closure that registers providers via ``OwnIDProvidersRegistrar``.
    /// - Returns: The same namespace type scoped for the returned child scope, or the current namespace unchanged when
    ///   empty.
    public func withProviders(_ block: (inout OwnIDProvidersRegistrar) -> Void) -> Self {
        withProviders("Providers", block)
    }
}

/// Contract for namespaces that can update providers in place.
public protocol ProvidersOverride {
    /// Updates providers in the current scope.
    ///
    /// Unlike ``ProvidersScope/withProviders(_:_:)``, this does not create a child scope.
    ///
    /// Merge semantics:
    /// - Providers declared in `block` replace providers of the same type in the current scope.
    /// - Existing providers of supported types that are not declared in `block` remain unchanged.
    ///
    /// If `block` does not register any providers, returns the current namespace unchanged.
    ///
    /// OwnID does not handle failures triggered by `block`.
    ///
    /// - Parameter block: Closure that registers providers via ``OwnIDProvidersRegistrar``.
    /// - Returns: The namespace for the updated current scope.
    func setProviders(_ block: (inout OwnIDProvidersRegistrar) -> Void) -> Self
}

internal protocol OwnIDNamespaceSupport: OwnIDNamespace, ContextScopeSupport, ProvidersScopeSupport {}

internal protocol ContextScopeSupport: ContextScope {
    var container: any DIContainer { get }

    func rebind(container: any DIContainer) -> Self
}

extension ContextScopeSupport {
    public func withContext(_ scopeName: String, _ block: (inout Context.Builder) -> Void) -> Self {
        rebind(container: container.withContext(scopeName, block))
    }
}

internal protocol ContextOverrideSupport: ContextOverride {
    var container: any DIContainer { get }
}

extension ContextOverrideSupport {
    public func setContext(_ block: (inout Context.Builder) -> Void) -> Self {
        _ = container.setContext(block)
        return self
    }

    public func clearContext() -> Self {
        _ = container.clearContext()
        return self
    }
}

internal protocol ProvidersScopeSupport: ProvidersScope {
    var container: any DIContainer { get }

    func rebind(container: any DIContainer) -> Self
}

extension ProvidersScopeSupport {
    public func withProviders(_ scopeName: String, _ block: (inout OwnIDProvidersRegistrar) -> Void) -> Self {
        let scopedContainer = container.withProviders(scopeName, block)
        if (scopedContainer as AnyObject) === (container as AnyObject) {
            return self
        }

        return rebind(container: scopedContainer)
    }
}

internal protocol ProvidersOverrideSupport: ProvidersOverride {
    var container: any DIContainer { get }
}

extension ProvidersOverrideSupport {
    public func setProviders(_ block: (inout OwnIDProvidersRegistrar) -> Void) -> Self {
        _ = container.setProviders(block)
        return self
    }
}
