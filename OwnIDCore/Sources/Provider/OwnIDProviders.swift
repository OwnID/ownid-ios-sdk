import Foundation
import UIKit

/// Registrar for OwnID provider implementations.
///
/// Use this registrar only inside ``OwnID/setProviders(_:)`` or ``OwnID/withProviders(_:_:)`` blocks.
/// ``OwnID/withProviders(_:_:)`` creates a child scope whose providers override inherited providers of the same type;
/// ``OwnID/setProviders(_:)`` updates the current scope in place.
///
/// Supported provider types are ``SessionCreate``, ``PasswordAuthenticate``, and ``SignInWithGoogle``. Registering the
/// same provider type more than once in one block uses the last provider. A block that registers no providers leaves the
/// current scope unchanged.
///
/// Do not retain this registrar or provider builders after the enclosing provider block returns. Keep app-owned state in
/// the handlers passed to the builder. OwnID keeps only the providers built from those handlers; the app owns their
/// external SDK/session state and failure mapping. Provider callbacks run on the main actor where their protocol
/// requires it.
///
/// ``SignInWithApple`` is registered by OwnID Core and is not configured through this registrar.
public struct OwnIDProvidersRegistrar {
    private let resolver: any DIContainerResolver

    private var sessionCreate: (any SessionCreate)?
    private var passwordAuthenticate: (any PasswordAuthenticate)?
    private var signInWithGoogle: (any SignInWithGoogle)?

    internal init(resolver: any DIContainerResolver) {
        self.resolver = resolver
    }

    /// Returns the dependency of type `T` from the current provider scope, or `nil` when it is missing.
    ///
    /// Use this typed lookup to read capabilities already available to the registrar while configuring providers.
    /// During ``OwnID/withProviders(_:_:)``, lookup reads from the parent scope being extended; providers registered
    /// later in the same block are not visible during that block.
    ///
    /// - Parameter type: Dependency type to resolve. Defaults to `T.self`.
    /// - Returns: The resolved dependency, or `nil` when it is missing.
    public func getOrNil<T: Sendable>(type: T.Type = T.self) -> T? {
        resolver.getOrNil(type: type)
    }

    /// Returns the dependency of type `T` from the current provider scope, or throws when resolution fails.
    ///
    /// Use this typed lookup when provider configuration cannot proceed without that dependency. During
    /// ``OwnID/withProviders(_:_:)``, lookup reads from the parent scope being extended; providers registered later in
    /// the same block are not visible during that block.
    ///
    /// - Parameter type: Dependency type to resolve. Defaults to `T.self`.
    /// - Returns: The resolved dependency.
    /// - Throws: ``MissingDependencyError`` when the dependency is not registered in the current provider scope;
    ///   ``DependencyResolutionError`` when resolution fails for another reason.
    public func getOrThrow<T: Sendable>(type: T.Type = T.self) throws -> T {
        try resolver.getOrThrow(type: type)
    }

    /// Registers the ``SessionCreate`` provider for this registrar.
    ///
    /// If called multiple times, the last provider wins. The block must set a `create` handler; omitting it fails a
    /// precondition before registration completes.
    ///
    /// - Parameter block: Configuration block for the provider.
    public mutating func sessionCreate(_ block: (inout SessionCreateBuilder) -> Void) {
        var builder = SessionCreateBuilder()
        block(&builder)
        sessionCreate = builder.build()
    }

    /// Registers the ``PasswordAuthenticate`` provider for this registrar.
    ///
    /// If called multiple times, the last provider wins. The block must set an `authenticate` handler; omitting it fails
    /// a precondition before registration completes.
    ///
    /// - Parameter block: Configuration block for the provider.
    public mutating func passwordAuthenticate(_ block: (inout PasswordAuthenticateBuilder) -> Void) {
        var builder = PasswordAuthenticateBuilder()
        block(&builder)
        passwordAuthenticate = builder.build()
    }

    /// Registers the ``SignInWithGoogle`` provider for this registrar.
    ///
    /// If called multiple times, the last provider wins. The block must set a `signIn` handler; omitting it fails a
    /// precondition before registration completes.
    ///
    /// - Parameter block: Configuration block for the provider.
    public mutating func signInWithGoogle(_ block: (inout SignInWithGoogleBuilder) -> Void) {
        var builder = SignInWithGoogleBuilder()
        block(&builder)
        signInWithGoogle = builder.build()
    }

    internal func register(into registrar: any DIContainerRegistrar) {
        if let sessionCreate { registrar.register((any SessionCreate).self, instance: sessionCreate) }
        if let passwordAuthenticate { registrar.register((any PasswordAuthenticate).self, instance: passwordAuthenticate) }
        if let signInWithGoogle { registrar.register((any SignInWithGoogle).self, instance: signInWithGoogle) }
    }

    internal var isEmpty: Bool {
        sessionCreate == nil && passwordAuthenticate == nil && signInWithGoogle == nil
    }

}

/// Builds a ``SessionCreate`` provider for the current registration block.
///
/// `create` is required. ``isAvailable(_:)`` is optional and defaults to available. The resulting provider is available
/// for `nil` params, delegates typed ``SessionCreateParams`` to ``isAvailable(_:)``, and reports unavailable for other
/// parameter types. OwnID invokes these callbacks on the main actor.
///
/// When ``isAvailable(_:)`` returns `false`, OwnID treats this provider as unavailable for the requested parameters.
/// OwnID does not retry session creation or persist returned session values.
public struct SessionCreateBuilder {
    private var availability: @Sendable @MainActor (SessionCreateParams) async -> Bool = { _ in true }
    private var createHandler: (@Sendable @MainActor (SessionCreateParams) async -> Result<SessionOutput, any Error & Sendable>)?

    /// Sets the availability check for this provider. If omitted, the provider is available.
    public mutating func isAvailable(_ block: @escaping @Sendable @MainActor (SessionCreateParams) async -> Bool) { availability = block }

    /// Sets the session creation handler.
    ///
    /// Return `Result.success` with ``SessionOutput`` when session creation succeeds, or `Result.failure` when it fails.
    /// The app owns the failure value.
    public mutating func create(
        _ block: @escaping @Sendable @MainActor (SessionCreateParams) async -> Result<SessionOutput, any Error & Sendable>
    ) { createHandler = block }

    internal func build() -> any SessionCreate {
        guard let createHandler else { preconditionFailure("sessionCreate requires a create handler") }
        return SessionCreateClosure(availability: availability, createHandler: createHandler)
    }
}

internal struct SessionCreateClosure: SessionCreate {
    internal let availability: @Sendable @MainActor (SessionCreateParams) async -> Bool
    internal let createHandler: @Sendable @MainActor (SessionCreateParams) async -> Result<SessionOutput, any Error & Sendable>

    @MainActor public func isAvailable(params: (any CapabilityParams)?) async -> Bool {
        guard let params else { return true }
        guard let typed = params as? SessionCreateParams else { return false }
        return await availability(typed)
    }

    @MainActor public func create(params: SessionCreateParams) async -> Result<SessionOutput, any Error & Sendable> {
        await createHandler(params)
    }
}

/// Builds a ``PasswordAuthenticate`` provider for the current registration block.
///
/// `authenticate` is required. ``isAvailable(_:)`` is optional and defaults to available. The resulting provider is
/// available for `nil` params, delegates typed ``PasswordAuthenticateParams`` to ``isAvailable(_:)``, and reports
/// unavailable for other parameter types. OwnID invokes these callbacks on the main actor.
///
/// When ``isAvailable(_:)`` returns `false`, OwnID treats this provider as unavailable for the requested parameters.
/// OwnID does not retry password authentication or persist returned session values.
public struct PasswordAuthenticateBuilder {
    private var availability: @Sendable @MainActor (PasswordAuthenticateParams) async -> Bool = { _ in true }
    private var authenticateHandler:
        (@Sendable @MainActor (PasswordAuthenticateParams) async -> Result<SessionOutput, any Error & Sendable>)?

    /// Sets the availability check for this provider. If omitted, the provider is available.
    public mutating func isAvailable(_ block: @escaping @Sendable @MainActor (PasswordAuthenticateParams) async -> Bool) {
        availability = block
    }

    /// Sets the password authentication handler.
    ///
    /// Return `Result.success` with ``SessionOutput`` when authentication succeeds, or `Result.failure` when authentication fails.
    /// The app owns the failure value.
    public mutating func authenticate(
        _ block: @escaping @Sendable @MainActor (PasswordAuthenticateParams) async -> Result<SessionOutput, any Error & Sendable>
    ) { authenticateHandler = block }

    internal func build() -> any PasswordAuthenticate {
        guard let authenticateHandler else { preconditionFailure("passwordAuthenticate requires an authenticate handler") }
        return PasswordAuthenticateClosure(availability: availability, authenticateHandler: authenticateHandler)
    }
}

internal struct PasswordAuthenticateClosure: PasswordAuthenticate {
    internal let availability: @Sendable @MainActor (PasswordAuthenticateParams) async -> Bool
    internal let authenticateHandler: @Sendable @MainActor (PasswordAuthenticateParams) async -> Result<SessionOutput, any Error & Sendable>

    @MainActor public func isAvailable(params: (any CapabilityParams)?) async -> Bool {
        guard let params else { return true }
        guard let typed = params as? PasswordAuthenticateParams else { return false }
        return await availability(typed)
    }

    @MainActor public func authenticate(params: PasswordAuthenticateParams) async -> Result<SessionOutput, any Error & Sendable> {
        await authenticateHandler(params)
    }
}

/// Builds a ``SignInWithGoogle`` provider for the current registration block.
///
/// `signIn` is required. ``isAvailable(_:)`` defaults to available, ``cancel(_:)`` defaults to a no-op, and
/// ``signOut(_:)`` defaults to a no-op. The resulting provider is available for `nil` params, delegates typed
/// ``SignInWithSocialParams`` to ``isAvailable(_:)``, and reports unavailable for other parameter types.
///
/// OwnID invokes `signIn`, `cancel`, and `signOut` on the main actor. `isAvailable` is not main-actor isolated; dispatch
/// to the main actor inside that closure when the provider SDK requires UI access.
/// The provider owns cancellation support, local provider session state, ID-token handling, and failure mapping.
public struct SignInWithGoogleBuilder {
    private var availability: @Sendable (SignInWithSocialParams) async -> Bool = { _ in true }
    private var signInHandler: (@Sendable @MainActor (SignInWithSocialParams) async -> SocialResult)?
    private var cancelHandler: @Sendable @MainActor () -> Void = {}
    private var signOutHandler: @Sendable @MainActor () -> Void = {}

    /// Sets the availability check for this provider. If omitted, the provider is available.
    public mutating func isAvailable(_ block: @escaping @Sendable (SignInWithSocialParams) async -> Bool) { availability = block }

    /// Sets the Google sign-in handler.
    public mutating func signIn(_ block: @escaping @Sendable @MainActor (SignInWithSocialParams) async -> SocialResult) {
        signInHandler = block
    }

    /// Sets the cancellation handler. If omitted, cancellation is a no-op.
    public mutating func cancel(_ block: @escaping @Sendable @MainActor () -> Void) { cancelHandler = block }

    /// Sets the Google sign-out handler. If omitted, sign-out is a no-op.
    public mutating func signOut(_ block: @escaping @Sendable @MainActor () -> Void) { signOutHandler = block }

    internal func build() -> any SignInWithGoogle {
        guard let signInHandler else { preconditionFailure("signInWithGoogle requires a signIn handler") }
        return SignInWithGoogleClosure(
            availability: availability,
            signInHandler: signInHandler,
            cancelHandler: cancelHandler,
            signOutHandler: signOutHandler
        )
    }
}

internal struct SignInWithGoogleClosure: SignInWithGoogle {
    internal let availability: @Sendable (SignInWithSocialParams) async -> Bool
    internal let signInHandler: @Sendable @MainActor (SignInWithSocialParams) async -> SocialResult
    internal let cancelHandler: @Sendable @MainActor () -> Void
    internal let signOutHandler: @Sendable @MainActor () -> Void

    public func isAvailable(params: (any CapabilityParams)?) async -> Bool {
        guard let params else { return true }
        guard let typed = params as? SignInWithSocialParams else { return false }
        return await availability(typed)
    }

    @MainActor public func signIn(params: SignInWithSocialParams) async -> SocialResult {
        await signInHandler(params)
    }

    @MainActor public func cancel() {
        cancelHandler()
    }

    @MainActor public func signOut() {
        signOutHandler()
    }
}

extension DIContainerRegistrar where Self: DIContainerResolver {

    /// Creates a child scope and registers providers from `block` in that scope.
    ///
    /// The child scope keeps the current scope's providers and configuration available. Providers declared in `block`
    /// replace providers of the same type only in that child scope. If the same provider type is registered more than once in
    /// `block`, the last provider wins.
    ///
    /// Supported provider types are ``SessionCreate``, ``PasswordAuthenticate``, and ``SignInWithGoogle``.
    ///
    /// If no providers are defined, returns this container.
    ///
    /// - Parameters:
    ///   - scopeName: Name for the child scope.
    ///   - block: Configuration block to register providers.
    /// - Returns: A `DIContainer` with the registered providers, or this container if none were defined.
    public func withProviders(_ scopeName: String = "Providers", _ block: (inout OwnIDProvidersRegistrar) -> Void) -> any DIContainer {
        var registrar = OwnIDProvidersRegistrar(resolver: self)
        block(&registrar)

        if registrar.isEmpty {
            return self
        }

        let child = createScope(scopeName: scopeName)
        registrar.register(into: child)
        return child
    }

    /// Updates providers in the current scope in place.
    ///
    /// Unlike ``withProviders(_:_:)``, this does not create a child scope.
    ///
    /// Merge semantics:
    /// - Providers declared in `block` replace providers of the same type in the current scope.
    /// - If the same provider type is registered more than once in `block`, the last provider wins.
    /// - Existing supported providers not declared in `block` remain unchanged.
    ///
    /// If no providers are defined, this is a no-op.
    ///
    /// - Parameter block: Configuration block to register providers.
    /// - Returns: This container.
    public func setProviders(_ block: (inout OwnIDProvidersRegistrar) -> Void) -> Self {
        var registrar = OwnIDProvidersRegistrar(resolver: self)
        block(&registrar)

        if registrar.isEmpty {
            return self
        }

        registrar.register(into: self)

        return self
    }
}
