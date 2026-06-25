import Foundation

internal protocol DIResolvable {
    func canResolve() -> Bool

    func getUnsatisfiedDependencies() -> [String]?
}

/// Direct namespace entry for calling one OwnID API.
///
/// Use a direct API entry from an initialized OwnID instance when you want the raw API contract instead of an operation
/// or flow.
/// Direct API entries return ``APIResult`` and do not create an operation or flow controller.
/// Expected failures and Swift task cancellation are reported in the returned ``APIResult``.
/// ``start(params:)`` resolves the bound API runtime and returns ``APIResult`` for the request outcome.
public struct APIEntry<Params, Success: Sendable, Failure: Sendable>: Sendable, DIResolvable {
    private let resolver: any DIContainerResolver
    private let runtimeType: Any.Type
    private let startProvider: @Sendable (Params) async -> APIResult<Success, Failure>

    internal init(
        resolver: any DIContainerResolver,
        runtimeType: Any.Type,
        startProvider: @escaping @Sendable (Params) async -> APIResult<Success, Failure>
    ) {
        self.resolver = resolver
        self.runtimeType = runtimeType
        self.startProvider = startProvider
    }

    /// Calls the underlying API.
    ///
    /// The request runs in the caller's task. Cancel the surrounding task to cancel the request.
    ///
    /// - Parameter params: Request parameters for this API.
    /// - Returns: ``APIResult/success(_:)`` with the API payload, ``APIResult/failure(_:)`` when the request fails,
    ///   or ``APIResult/canceled`` if the surrounding task is canceled before completion.
    public func start(params: Params) async -> APIResult<Success, Failure> {
        await startProvider(params)
    }

    internal func canResolve() -> Bool {
        resolver.canResolve(runtimeType)
    }

    internal func getUnsatisfiedDependencies() -> [String]? {
        resolver.getUnsatisfiedDependencies(for: runtimeType)
    }
}

extension APIEntry {
    /// Calls the API without passing an explicit parameter object.
    ///
    /// - Returns: ``APIResult/success(_:)`` with the API payload, ``APIResult/failure(_:)`` when the request fails,
    ///   or ``APIResult/canceled`` if the surrounding task is canceled before completion.
    public func start<Wrapped>() async -> APIResult<Success, Failure> where Params == Wrapped? {
        await start(params: nil)
    }
}

/// Direct namespace entry for a single OwnID operation.
///
/// Use ``availability(params:)`` or ``isAvailable(params:)`` to check readiness for specific parameters, and call
/// ``start(params:)`` to launch the operation.
/// The returned ``OperationController`` is owned by the caller; keep it while the operation is active and use
/// ``OperationController/whenSettled()`` to await the terminal result.
/// Each ``start(params:)`` call resolves a fresh operation runtime from the bound scope and returns a caller-owned
/// controller for that run.
/// Use optional parameter types for operations that support the zero-argument convenience overloads.
public protocol OperationEntry<Params, Success, Failure>: Sendable {
    associatedtype Params
    associatedtype Success: Sendable
    associatedtype Failure: OperationFailure

    /// Type of the operation.
    var operationType: OperationType { get }

    /// Returns whether the operation can start with `params`.
    ///
    /// If unavailable, the result carries a human-readable message explaining what the integrator needs to provide
    /// or change before calling ``start(params:)``. Missing or unresolved entry dependencies are returned as
    /// ``Availability/unavailable(_:)``.
    ///
    /// Availability is a preflight check only. ``start(params:)`` still resolves the bound scope at launch time and
    /// traps if dependencies are missing or cannot be resolved.
    func availability(params: Params) async -> Availability

    /// Starts the operation.
    ///
    /// - Returns: A controller for this operation instance.
    /// - Warning: Traps if the operation runtime cannot be resolved from the bound scope.
    func start(params: Params) -> any OperationController<Success, Failure>
}

/// Operation entry that can create operation-local dependency scopes.
///
/// This is an internal SDK module contract, not a public app integration contract. Optional UI modules use it to bind
/// operation-local dependencies without mutating the owning instance scope or sibling operation scopes.
@_spi(OwnIDInternal)
public protocol ScopedOperationEntry: OperationEntry {
    /// Name of the OwnID SDK instance that owns this operation entry.
    var instanceName: InstanceName { get }

    /// Creates an operation-local scope and returns an entry that starts operations from that scope.
    ///
    /// Dependencies registered in `configure` are visible only to operations started from the returned entry. The parent
    /// instance scope and sibling operation scopes are not mutated.
    ///
    /// - Note: The erased `Any` return is intentional. `ScopedOperationEntry` is consumed through `any
    ///   ScopedOperationEntry` existentials by other SDK modules, and parameterized protocol existentials/casts are not
    ///   runtime-safe on iOS 13-15. Keep this erased until the SDK drops support for iOS versions earlier than 16.
    func withOperationScope(_ scopeName: String, configure: @escaping @Sendable (any DIContainer) -> Void) -> Any
}

/// Type-erased scoped operation entry used by SDK modules that need operation-local dependency scopes.
@_spi(OwnIDInternal)
public struct AnyScopedOperationEntry<Params, Success: Sendable, Failure: OperationFailure>: OperationEntry, ScopedOperationEntry,
    DIResolvable
{
    private let entry: any OperationEntry<Params, Success, Failure>
    private let scoped: any ScopedOperationEntry

    public var operationType: OperationType { entry.operationType }
    public var instanceName: InstanceName { scoped.instanceName }

    internal init<Entry: ScopedOperationEntry>(_ entry: Entry)
    where Entry.Params == Params, Entry.Success == Success, Entry.Failure == Failure {
        self.entry = entry
        self.scoped = entry
    }

    public func availability(params: Params) async -> Availability {
        await entry.availability(params: params)
    }

    public func start(params: Params) -> any OperationController<Success, Failure> {
        entry.start(params: params)
    }

    public func withOperationScope(_ scopeName: String, configure: @escaping @Sendable (any DIContainer) -> Void) -> Any {
        return scoped.withOperationScope(scopeName, configure: configure)
    }

    internal func canResolve() -> Bool {
        (entry as? any DIResolvable)?.canResolve() ?? false
    }

    internal func getUnsatisfiedDependencies() -> [String]? {
        (entry as? any DIResolvable)?.getUnsatisfiedDependencies()
    }
}

extension OperationEntry {
    /// Returns `true` if the operation can be started with `params`.
    public func isAvailable(params: Params) async -> Bool {
        if case .available = await availability(params: params) { return true }
        return false
    }

    /// Returns availability without passing an explicit parameter object.
    public func availability<Wrapped>() async -> Availability where Params == Wrapped? {
        await availability(params: nil)
    }

    /// Returns `true` when the operation can be started without passing an explicit parameter object.
    public func isAvailable<Wrapped>() async -> Bool where Params == Wrapped? {
        await isAvailable(params: nil)
    }

    /// Starts an operation whose parameter type is optional without passing an explicit parameter object.
    ///
    /// - Warning: Traps if the operation runtime cannot be resolved from the bound scope.
    public func start<Wrapped>() -> any OperationController<Success, Failure> where Params == Wrapped? {
        start(params: nil)
    }

    internal func canResolve() -> Bool {
        (self as? any DIResolvable)?.canResolve() ?? false
    }

    internal func getUnsatisfiedDependencies() -> [String]? {
        (self as? any DIResolvable)?.getUnsatisfiedDependencies()
    }
}

private struct OperationEntryImpl<Runtime: Any & Sendable, Params, Success: Sendable, Failure: OperationFailure>: OperationEntry,
    DIResolvable
{
    let container: any DIContainer
    let runtimeType: Runtime.Type
    let availabilityProvider: @Sendable (Runtime, Params) async -> Availability
    let startProvider: @Sendable (Runtime, Params) -> any OperationController<Success, Failure>

    let operationType: OperationType

    init(
        container: any DIContainer,
        runtimeType: Runtime.Type,
        operationType: OperationType,
        availabilityProvider: @escaping @Sendable (Runtime, Params) async -> Availability,
        startProvider: @escaping @Sendable (Runtime, Params) -> any OperationController<Success, Failure>
    ) {
        self.container = container
        self.runtimeType = runtimeType
        self.operationType = operationType
        self.availabilityProvider = availabilityProvider
        self.startProvider = startProvider
    }

    func availability(params: Params) async -> Availability {
        do {
            let runtime = try container.getOrThrow(type: runtimeType)
            return await availabilityProvider(runtime, params)
        } catch is MissingDependencyError {
            let details = container.getUnsatisfiedDependencies(for: runtimeType)?.joined(separator: ", ") ?? String(describing: runtimeType)
            return .unavailable("Missing dependencies: \(details)")
        } catch let error as DependencyResolutionError {
            return .unavailable(String(describing: error))
        } catch {
            return .unavailable(String(describing: error))
        }
    }

    func start(params: Params) -> any OperationController<Success, Failure> {
        let runtime = try! container.getOrThrow(type: runtimeType)
        return startProvider(runtime, params)
    }

    func canResolve() -> Bool {
        container.canResolve(runtimeType)
    }

    func getUnsatisfiedDependencies() -> [String]? {
        container.getUnsatisfiedDependencies(for: runtimeType)
    }

    func with(container: any DIContainer) -> Self {
        Self(
            container: container,
            runtimeType: runtimeType,
            operationType: operationType,
            availabilityProvider: availabilityProvider,
            startProvider: startProvider
        )
    }
}

private struct ScopedOperationEntryImpl<Runtime: Any & Sendable, Params, Success: Sendable, Failure: OperationFailure>:
    ScopedOperationEntry, DIResolvable
{
    private let delegate: OperationEntryImpl<Runtime, Params, Success, Failure>

    var operationType: OperationType { delegate.operationType }
    var instanceName: InstanceName { try! delegate.container.getOrThrow(type: InstanceName.self) }

    init(delegate: OperationEntryImpl<Runtime, Params, Success, Failure>) {
        self.delegate = delegate
    }

    func availability(params: Params) async -> Availability {
        await delegate.availability(params: params)
    }

    func start(params: Params) -> any OperationController<Success, Failure> {
        delegate.start(params: params)
    }

    func withOperationScope(_ scopeName: String, configure: @escaping @Sendable (any DIContainer) -> Void) -> Any {
        let scopedContainer = delegate.container.createScope(scopeName: scopeName)
        configure(scopedContainer)
        return AnyScopedOperationEntry(Self(delegate: delegate.with(container: scopedContainer)))
    }

    func canResolve() -> Bool {
        delegate.canResolve()
    }

    func getUnsatisfiedDependencies() -> [String]? {
        delegate.getUnsatisfiedDependencies()
    }
}

/// Direct namespace entry for a single OwnID flow.
///
/// Use ``start(_:)`` to launch the flow for the selected namespace member.
/// The returned controller is owned by the caller; keep it while the flow is active and use that flow controller's
/// settlement API to await the final result.
/// Entry creation does not resolve the underlying runtime; ``start(_:)`` resolves it from the bound scope.
/// Use optional context types for flows that support the zero-argument convenience overload.
public struct FlowEntry<Context, Controller>: Sendable, DIResolvable {
    private let resolver: any DIContainerResolver
    private let runtimeType: Any.Type
    private let startProvider: @Sendable (Context) -> Controller

    internal init(
        resolver: any DIContainerResolver,
        runtimeType: Any.Type,
        startProvider: @escaping @Sendable (Context) -> Controller
    ) {
        self.resolver = resolver
        self.runtimeType = runtimeType
        self.startProvider = startProvider
    }

    /// Starts the flow.
    ///
    /// - Returns: A controller for the running flow.
    /// - Warning: Traps if the flow runtime cannot be resolved from the bound scope.
    public func start(_ context: Context) -> Controller {
        startProvider(context)
    }

    internal func canResolve() -> Bool {
        resolver.canResolve(runtimeType)
    }

    internal func getUnsatisfiedDependencies() -> [String]? {
        resolver.getUnsatisfiedDependencies(for: runtimeType)
    }
}

extension FlowEntry {
    /// Starts a flow whose context type is optional without passing an explicit context object.
    ///
    /// - Warning: Traps if the flow runtime cannot be resolved from the bound scope.
    public func start<Wrapped>() -> Controller where Context == Wrapped? {
        start(nil)
    }
}

/// Direct namespace entry for a flow that supports runtime preflight checks.
///
/// Use ``availability(_:)`` or ``isAvailable(_:)`` to check readiness for a specific context before calling
/// ``start(_:)``.
/// Entry creation does not resolve the underlying runtime; ``availability(_:)`` and ``start(_:)`` resolve it from the
/// bound scope.
public struct PreflightFlowEntry<Context, Controller>: Sendable, DIResolvable {
    private let resolver: any DIContainerResolver
    private let runtimeType: Any.Type
    private let availabilityProvider: @Sendable (Context) async -> Availability
    private let startProvider: @Sendable (Context) -> Controller

    internal init(
        resolver: any DIContainerResolver,
        runtimeType: Any.Type,
        availabilityProvider: @escaping @Sendable (Context) async -> Availability,
        startProvider: @escaping @Sendable (Context) -> Controller
    ) {
        self.resolver = resolver
        self.runtimeType = runtimeType
        self.availabilityProvider = availabilityProvider
        self.startProvider = startProvider
    }

    /// Returns whether the flow can start with `context`.
    ///
    /// If unavailable, the result carries a human-readable message explaining what the integrator needs to provide
    /// or change before calling ``start(_:)``. Missing or unresolved entry dependencies are returned as
    /// ``Availability/unavailable(_:)``.
    ///
    /// Availability is a preflight check only. ``start(_:)`` still resolves the bound scope at launch time and traps
    /// if dependencies are missing or cannot be resolved.
    public func availability(_ context: Context) async -> Availability {
        await availabilityProvider(context)
    }

    /// Returns `true` if the flow can be started with `context`.
    public func isAvailable(_ context: Context) async -> Bool {
        if case .available = await availability(context) { return true }
        return false
    }

    /// Starts the flow.
    ///
    /// - Warning: Traps if the flow runtime cannot be resolved from the bound scope.
    public func start(_ context: Context) -> Controller {
        startProvider(context)
    }

    internal func canResolve() -> Bool {
        resolver.canResolve(runtimeType)
    }

    internal func getUnsatisfiedDependencies() -> [String]? {
        resolver.getUnsatisfiedDependencies(for: runtimeType)
    }
}

extension PreflightFlowEntry {
    /// Checks flow availability without passing an explicit context object.
    public func availability<Wrapped>() async -> Availability where Context == Wrapped? {
        await availability(nil)
    }

    /// Returns `true` when the flow can be started without passing an explicit context object.
    public func isAvailable<Wrapped>() async -> Bool where Context == Wrapped? {
        await isAvailable(nil)
    }

    /// Starts a flow whose context type is optional without passing an explicit context object.
    ///
    /// - Warning: Traps if the flow runtime cannot be resolved from the bound scope.
    public func start<Wrapped>() -> Controller where Context == Wrapped? {
        start(nil)
    }
}

internal func apiEntry<Runtime: Any & Sendable, Params, Success, Failure>(
    container: any DIContainer,
    runtimeType: Runtime.Type,
    start: @escaping @Sendable (Runtime, Params) async -> APIResult<Success, Failure>
) -> APIEntry<Params, Success, Failure> {
    APIEntry(
        resolver: container,
        runtimeType: runtimeType,
        startProvider: { params in
            let runtime = try! container.getOrThrow(type: runtimeType)
            return await start(runtime, params)
        }
    )
}

internal func operationEntry<Runtime: Any & Sendable, Params, Success: Sendable, Failure: OperationFailure>(
    container: any DIContainer,
    runtimeType: Runtime.Type,
    operationType: OperationType,
    availability: @escaping @Sendable (Runtime, Params) async -> Availability,
    start: @escaping @Sendable (Runtime, Params) -> any OperationController<Success, Failure>
) -> any OperationEntry<Params, Success, Failure> {
    OperationEntryImpl(
        container: container,
        runtimeType: runtimeType,
        operationType: operationType,
        availabilityProvider: availability,
        startProvider: start
    )
}

internal func scopedOperationEntry<Runtime: Any & Sendable, Params, Success: Sendable, Failure: OperationFailure>(
    container: any DIContainer,
    runtimeType: Runtime.Type,
    operationType: OperationType,
    availability: @escaping @Sendable (Runtime, Params) async -> Availability,
    start: @escaping @Sendable (Runtime, Params) -> any OperationController<Success, Failure>
) -> any OperationEntry<Params, Success, Failure> {
    ScopedOperationEntryImpl(
        delegate: OperationEntryImpl(
            container: container,
            runtimeType: runtimeType,
            operationType: operationType,
            availabilityProvider: availability,
            startProvider: start
        )
    )
}

internal func flowEntry<Runtime: Any & Sendable, Context, Controller>(
    container: any DIContainer,
    runtimeType: Runtime.Type,
    start: @escaping @Sendable (Runtime, Context) -> Controller
) -> FlowEntry<Context, Controller> {
    FlowEntry(
        resolver: container,
        runtimeType: runtimeType,
        startProvider: { context in
            let runtime = try! container.getOrThrow(type: runtimeType)
            return start(runtime, context)
        }
    )
}

internal func preflightFlowEntry<Runtime: Any & Sendable, Context, Controller>(
    container: any DIContainer,
    runtimeType: Runtime.Type,
    availability: @escaping @Sendable (Runtime, Context) async -> Availability,
    start: @escaping @Sendable (Runtime, Context) -> Controller
) -> PreflightFlowEntry<Context, Controller> {
    PreflightFlowEntry(
        resolver: container,
        runtimeType: runtimeType,
        availabilityProvider: { context in
            do {
                let runtime = try container.getOrThrow(type: runtimeType)
                return await availability(runtime, context)
            } catch is MissingDependencyError {
                let details =
                    container.getUnsatisfiedDependencies(for: runtimeType)?.joined(separator: ", ") ?? String(describing: runtimeType)
                return .unavailable("Missing dependencies: \(details)")
            } catch let error as DependencyResolutionError {
                return .unavailable(String(describing: error))
            } catch {
                return .unavailable(String(describing: error))
            }
        },
        startProvider: { context in
            let runtime = try! container.getOrThrow(type: runtimeType)
            return start(runtime, context)
        }
    )
}
