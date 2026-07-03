import Foundation

/// Instance-scoped runtime for one ``PasskeyEnrollOperation`` lifecycle.
///
/// The namespace entry creates a fresh runtime for each launch. This runtime registers its controller while the operation
/// is active, owns the enroll side effects for that run, and unregisters after the controller settles or cleanup
/// completes. Abort requests are operation-owned cancellation inputs; callers must observe settlement through the
/// controller.
internal final class PasskeyEnrollOperationImpl: PasskeyEnrollOperation, @unchecked Sendable {
    enum Event: Sendable {
        case start(PasskeyEnrollOperationParams?)
        case abort(Reason)
        case complete(OperationResult<Void, PasskeyEnrollOperationFailure>)
    }

    internal let operationType: OperationType
    internal let operationID: OperationID
    private let operationRegistry: OperationRegistryImpl
    private let api: any PasskeyEnrollAPI
    private let taskScope: TaskScope
    private let context: Context?
    private let logger: OwnIDLogRouter?
    private let unsatisfiedDependencies: [String]?

    @MainActor @BroadcastedState private var state: PasskeyEnrollOperationState = .created
    @MainActor internal func stateStream() -> AsyncStream<PasskeyEnrollOperationState> { _state.stream() }

    private let stream = OperationEventStream<Event>()

    private lazy var controllerImpl: OperationControllerImpl<Void, PasskeyEnrollOperationFailure> = {
        let controller = OperationControllerImpl<Void, PasskeyEnrollOperationFailure>(operationID: operationID) { [weak self] reason in
            guard let self else { return }
            taskScope.spawn { await self.stream.yield(.abort(reason)) }
        }
        controller._attachOwner(self)
        return controller
    }()

    internal var controller: PasskeyEnrollOperationController { controllerImpl }

    internal init(
        operationType: OperationType,
        operationRegistry: OperationRegistryImpl,
        api: any PasskeyEnrollAPI,
        taskScope: TaskScope,
        context: Context?,
        logger: OwnIDLogRouter?,
        unsatisfiedDependencies: [String]? = nil
    ) {
        self.operationType = operationType
        self.operationID = operationType.createOperationID()
        self.operationRegistry = operationRegistry
        self.api = api
        self.taskScope = taskScope
        self.context = context
        self.logger = logger
        self.unsatisfiedDependencies = unsatisfiedDependencies

        taskScope.onShutdown { [weak self] in
            self?.handleShutdown()
        }

        taskScope.spawn(
            onCancel: { [stream = self.stream] in Task { await stream.finish() } }
        ) { [weak self, stream = self.stream] in
            for await event in stream.sequence {
                if Task.isCancelled { break }
                guard let self else { break }

                switch event {
                case .start(let params):
                    let state = await MainActor.run { self.state }
                    if case .created = state {
                        await MainActor.run { self.operationRegistry.register(controller: self.controller) }
                        await MainActor.run { self.state = .preparing }

                        guard let params else {
                            await self.stream.yield(
                                .complete(
                                    .failure(
                                        PasskeyEnrollOperationFailure.input(
                                            .missingTokens(errorCode: .invalidArgument, message: "AccessToken and ProofToken required")
                                        )
                                    )
                                )
                            )
                            continue
                        }

                        taskScope.spawn { [weak self] in
                            guard let self else { return }
                            guard let accessToken = params.accessToken ?? self.context?.accessToken else {
                                guard await self.isAlive() else { return }
                                await self.stream.yield(
                                    .complete(
                                        .failure(
                                            PasskeyEnrollOperationFailure.input(
                                                .missingTokens(errorCode: .invalidArgument, message: "AccessToken and ProofToken required")
                                            )
                                        )
                                    )
                                )
                                return
                            }
                            let apiResult = await self.api.start(
                                params: PasskeyEnrollAPIParams(
                                    proofToken: params.proofToken,
                                    accessToken: accessToken,
                                    traceParent: params.traceParent ?? TraceContext.generateTraceParent()
                                )
                            )
                            if case .failure(let apiError) = apiResult {
                                self.logger?.logI(
                                    source: self,
                                    prefix: "Event.Start",
                                    message: "API start failed: \(apiError.message)"
                                )
                            }
                            guard await self.isAlive() else { return }
                            await self.stream.yield(
                                .complete(
                                    apiResult.fold(
                                        onSuccess: OperationResult.success,
                                        onError: { apiError in .failure(apiError.toOperationFailure()) },
                                        onCanceled: { .canceled(.systemError(details: "Operation canceled")) }
                                    )
                                )
                            )
                        }
                    }

                case .abort(let reason):
                    let state = await MainActor.run { self.state }
                    switch state {
                    case .created, .preparing:
                        await self.stream.yield(.complete(.canceled(reason)))
                    case .completed:
                        break
                    }

                case .complete(let result):
                    let didSettle = await self.markCompletedIfNeeded(result)
                    guard didSettle else { break }
                    await MainActor.run { self.operationRegistry.unregister(id: self.operationID) }
                    self.controllerImpl._releaseOwner()
                    result
                        .onSuccess { _ in self.controllerImpl.complete(()) }
                        .onCanceled { reason in
                            self.logger?.logD(source: self, prefix: "Canceled with reason", message: reason.description)
                            self.controllerImpl.cancel(reason)
                        }
                        .onError { error in
                            self.logger?.logD(source: self, prefix: "Completed with error", message: error.message)
                            self.controllerImpl.fail(error)
                        }
                    await self.stream.finish()
                }
            }
        }
    }

    deinit {
        taskScope.shutdown()
        self.logger?.logV(source: self, prefix: #function, message: "Invoked")
    }

    @discardableResult
    internal func start(params: PasskeyEnrollOperationParams? = nil) -> PasskeyEnrollOperationController {
        let stream = self.stream
        taskScope.spawn { [stream] in
            await stream.yield(.start(params))
        }
        return controller
    }

    internal func availability(params: (any CapabilityParams)?) async -> Availability {
        if let deps = unsatisfiedDependencies {
            return .unavailable("Missing dependencies: \(deps.joined(separator: ", "))")
        }

        let operationParams: PasskeyEnrollOperationParams?
        if let params {
            guard let typedParams = params as? PasskeyEnrollOperationParams else {
                return .unavailable("Unsupported params type: \(String(describing: type(of: params)))")
            }
            operationParams = typedParams
        } else {
            operationParams = nil
        }

        let accessToken = operationParams?.accessToken ?? context?.accessToken
        guard accessToken != nil, operationParams?.proofToken != nil else {
            return .unavailable("AccessToken and ProofToken required")
        }

        return .available
    }

    private func isAlive() async -> Bool {
        await MainActor.run { if case .completed = self.state { false } else { true } }
    }

    @MainActor
    private func markCompletedIfNeeded(_ result: OperationResult<Void, PasskeyEnrollOperationFailure>) -> Bool {
        if case .completed = self.state { return false }
        self.state = .completed(result: result)
        return true
    }

    private func handleShutdown() {
        Task { [weak self] in
            guard let self else { return }
            let reason = Reason.systemError(details: "Operation canceled")
            let didSettle = await self.markCompletedIfNeeded(.canceled(reason))
            guard didSettle else { return }
            await MainActor.run { self.operationRegistry.unregister(id: self.operationID) }
            self.controllerImpl._releaseOwner()
            self.controllerImpl.cancel(reason)
            await self.stream.finish()
        }
    }
}

extension PasskeyEnrollOperationImpl {

    internal static func create(resolver: any DIContainerResolver) -> any PasskeyEnrollOperation {
        do {
            let resolverWithContext = (resolver as! any DIContainer).withContext("PasskeyEnrollOperation") { _ in }
            return PasskeyEnrollOperationImpl(
                operationType: .passkeyEnrollment,
                operationRegistry: try resolver.getOrThrow(type: (any OperationRegistry).self) as! OperationRegistryImpl,
                api: try resolverWithContext.getOrThrow(type: (any PasskeyEnrollAPI).self),
                taskScope: try resolver.getOrThrow(type: TaskScope.self),
                context: resolver.getOrNil(type: Context.self),
                logger: resolver.getOrNil(type: OwnIDLogRouter.self),
                unsatisfiedDependencies: resolver.getUnsatisfiedDependencies(for: (any PasskeyEnrollOperation).self)
            )
        } catch {
            return Failed(error: error)
        }
    }
}

/// Unavailable operation returned when construction cannot provide a usable runtime.
///
/// Starting this object returns a controller that is already completed with ``PasskeyEnrollOperationFailure``, does not
/// register in ``OperationRegistry``, and reports unavailable with the same diagnostic message.
private final class Failed: PasskeyEnrollOperation, @unchecked Sendable {
    let operationType: OperationType = .passkeyEnrollment
    let operationID: OperationID = OperationType.passkeyEnrollment.createOperationID()
    let controller: PasskeyEnrollOperationController
    private let controllerImpl: OperationControllerImpl<Void, PasskeyEnrollOperationFailure>
    private let failure: PasskeyEnrollOperationFailure

    init(error: any Error) {
        let controller = OperationControllerImpl<Void, PasskeyEnrollOperationFailure>(operationID: operationID) { _ in }
        let failure = PasskeyEnrollOperationFailure.unexpected(message: String(describing: error), underlyingError: error.asSendableError())
        self.failure = failure
        controller.fail(failure)
        self.controllerImpl = controller
        self.controller = controller
    }

    @discardableResult
    func start(params: PasskeyEnrollOperationParams? = nil) -> PasskeyEnrollOperationController {
        controller
    }

    func availability(params: (any CapabilityParams)?) async -> Availability {
        .unavailable(failure.message)
    }

    @MainActor
    func stateStream() -> AsyncStream<PasskeyEnrollOperationState> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                let result = await controller.whenSettled()
                continuation.yield(.completed(result: result))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

extension PasskeyEnrollAPIFailure {
    fileprivate func toOperationFailure() -> PasskeyEnrollOperationFailure {
        switch self {
        case .badRequest(.invalidArgument(let errorCode, let message)), .badRequest(.unknown(let errorCode, let message)):
            return .input(.invalidRequest(errorCode: errorCode, message: message, apiFailure: self))
        case .forbidden(let errorCode, let message):
            return .access(.forbidden(errorCode: errorCode, message: message, apiFailure: self))
        case .userNotFound(let errorCode, let message):
            return .access(.userNotFound(errorCode: errorCode, message: message, apiFailure: self))
        case .failedDependency(.providerFailed(let errorCode, let message, _)):
            return .integration(.providerFailed(errorCode: errorCode, message: message, apiFailure: self))
        case .failedDependency(.missingProvider(let errorCode, let message, let capability, _)):
            return .integration(.missingProvider(errorCode: errorCode, message: message, capability: capability, apiFailure: self))
        case .unexpected(let errorCode, let message, let underlyingError):
            return .unexpected(errorCode: errorCode, message: message, apiFailure: self, underlyingError: underlyingError)
        }
    }
}
