import Foundation

internal final class SignInWithAppleOperationImpl: SignInWithAppleOperation, @unchecked Sendable {
    enum Event: Sendable {
        case start(SignInWithAppleOperationParams?)
        case signIn(SocialResult)
        case abort(Reason)
        case complete(OperationResult<AccessTokenWithUserInfo, SignInWithAppleOperationFailure>)
    }

    internal let operationType: OperationType
    internal let operationID: OperationID
    private let operationRegistry: OperationRegistryImpl
    private let ui: any SignInWithAppleUI
    private let api: any OIDCAPI
    private let taskScope: TaskScope
    private let context: Context?
    private let logger: OwnIDLogRouter?
    private let unsatisfiedDependencies: [String]?

    @MainActor @BroadcastedState private var state: SignInWithAppleOperationState = .created
    @MainActor internal func stateStream() -> AsyncStream<SignInWithAppleOperationState> { _state.stream() }

    private let stream = OperationEventStream<Event>()
    private enum TaskRefKey { case timeout, ui }
    private let taskRefs = OperationTaskRefs<TaskRefKey>()

    private lazy var controllerImpl: OperationControllerImpl<AccessTokenWithUserInfo, SignInWithAppleOperationFailure> = {
        let controller = OperationControllerImpl<AccessTokenWithUserInfo, SignInWithAppleOperationFailure>(operationID: operationID) {
            [weak self] reason in
            guard let self else { return }
            taskScope.spawn { await self.stream.yield(.abort(reason)) }
        }
        controller._attachOwner(self)
        return controller
    }()

    internal var controller: SignInWithAppleOperationController { controllerImpl }

    internal init(
        operationType: OperationType,
        operationRegistry: OperationRegistryImpl,
        ui: any SignInWithAppleUI,
        api: any OIDCAPI,
        taskScope: TaskScope,
        context: Context?,
        logger: OwnIDLogRouter?,
        unsatisfiedDependencies: [String]? = nil
    ) {
        self.operationType = operationType
        self.operationID = operationType.createOperationID()
        self.operationRegistry = operationRegistry
        self.ui = ui
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

                        taskScope.spawn { [weak self] in
                            guard let self else { return }
                            let params = params ?? SignInWithAppleOperationParams()
                            let apiResult = await self.api.start(
                                params: OIDCAPIParams(
                                    provider: .apple,
                                    accessToken: params.accessToken ?? self.context?.accessToken,
                                    traceParent: params.traceParent ?? TraceContext.generateTraceParent()
                                )
                            )
                            switch apiResult {
                            case .success(let apiController):
                                guard await self.isAlive() else { return }
                                self.taskRefs.replace(
                                    .timeout,
                                    with: taskScope.spawn { [weak self] in
                                        guard let self else { return }
                                        do {
                                            let total = UInt64(apiController.challenge.timeout.milliseconds) * 1_000_000 + 2_000_000_000
                                            try await Task.sleep(nanoseconds: total)
                                            await self.stream.yield(.abort(.timeout))
                                        } catch {}
                                    }
                                )
                                await MainActor.run { self.state = .active(apiController: apiController) }
                                let ui = self.ui
                                let clientID = apiController.challenge.clientID
                                let nonce = apiController.challenge.challengeID.value
                                self.taskRefs.replace(
                                    .ui,
                                    with: taskScope.spawnOnMain { [weak self] in
                                        guard let self else { return }
                                        guard await self.isAlive() else { return }
                                        let socialResult = await ui.signIn(clientID: clientID, nonce: nonce, window: nil)
                                        await self.stream.yield(.signIn(socialResult))
                                    }
                                )
                            case .failure(let apiError):
                                self.logger?.logI(
                                    source: self,
                                    prefix: "Event.Start",
                                    message: "OIDC start failed: \(apiError.message)"
                                )
                                await self.stream.yield(.complete(.failure(apiError.toAppleOperationFailure())))
                            case .canceled:
                                guard await self.isAlive() else { return }
                                await self.stream.yield(.complete(.canceled(.systemError(details: "Operation canceled"))))
                            }
                        }
                    }

                case .signIn(let socialResult):
                    let state = await MainActor.run { self.state }
                    switch state {
                    case .created, .preparing:
                        let error = self.unexpectedEventError(eventDescription: ".signIn", state: state)
                        await self.stream.yield(.complete(.failure(error)))
                    case .active(let apiController):
                        switch socialResult {
                        case .success(_, let idToken):
                            taskScope.spawn { [weak self] in
                                guard let self else { return }
                                let apiResult = await apiController.completeWithToken(idToken: idToken)
                                guard await self.isAlive() else { return }
                                await self.stream.yield(
                                    .complete(
                                        apiResult.fold(
                                            onSuccess: OperationResult.success,
                                            onError: { apiError in .failure(apiError.toAppleOperationFailure()) },
                                            onCanceled: { .canceled(.systemError(details: "Operation canceled")) }
                                        )
                                    )
                                )
                            }
                        case .canceled(let reason):
                            taskScope.spawn { [weak self] in
                                guard let self else { return }
                                let apiResult = await apiController.cancel(reason: reason)
                                switch apiResult {
                                case .success:
                                    break
                                case .failure(let error):
                                    self.logger?.logI(
                                        source: self,
                                        prefix: "Event.Abort",
                                        message: "API cancel failed after provider cancellation: \(error.message)"
                                    )
                                case .canceled:
                                    self.logger?.logI(
                                        source: self,
                                        prefix: "Event.Abort",
                                        message: "API cancel canceled after provider cancellation"
                                    )
                                }
                                await self.stream.yield(.complete(.canceled(reason)))
                            }
                        case .fail(let error):
                            taskScope.spawn { [weak self] in
                                guard let self else { return }
                                let apiResult = await apiController.cancel(reason: Reason.systemError(details: "Authorization failed"))
                                switch apiResult {
                                case .success:
                                    break
                                case .failure(let error):
                                    self.logger?.logI(
                                        source: self,
                                        prefix: "Event.Abort",
                                        message: "API cancel failed after provider failure: \(error.message)"
                                    )
                                case .canceled:
                                    self.logger?.logI(
                                        source: self,
                                        prefix: "Event.Abort",
                                        message: "API cancel canceled after provider failure"
                                    )
                                }
                                await self.stream.yield(
                                    .complete(
                                        .failure(
                                            SignInWithAppleOperationFailure.integration(
                                                .providerFailed(
                                                    errorCode: .oidcFailed,
                                                    message: String(describing: error),
                                                    underlyingError: error
                                                )
                                            )
                                        )
                                    )
                                )
                            }
                        }
                    case .completed:
                        break
                    }

                case .abort(let reason):
                    let state = await MainActor.run { self.state }
                    switch state {
                    case .created, .preparing: await self.stream.yield(.complete(.canceled(reason)))
                    case .active(let apiController):
                        taskScope.spawnOnMain { [weak self] in self?.ui.cancel() }
                        self.taskRefs.clear([.timeout, .ui])
                        taskScope.spawn { [weak self] in
                            guard let self else { return }
                            let apiResult = await apiController.cancel(reason: reason)
                            switch apiResult {
                            case .success:
                                break
                            case .failure(let error):
                                self.logger?.logI(
                                    source: self,
                                    prefix: "Event.Abort",
                                    message: "API cancel failed: \(error.message)"
                                )
                            case .canceled:
                                self.logger?.logI(source: self, prefix: "Event.Abort", message: "API cancel canceled")
                            }
                        }
                        await self.stream.yield(.complete(.canceled(reason)))
                    case .completed:
                        break
                    }

                case .complete(let result):
                    self.taskRefs.clear([.timeout, .ui])
                    let didSettle = await self.markCompletedIfNeeded(result)
                    guard didSettle else { break }
                    await MainActor.run { self.operationRegistry.unregister(id: self.operationID) }
                    self.controllerImpl._releaseOwner()
                    result
                        .onSuccess { payload in self.controllerImpl.complete(payload) }
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
    internal func start(params: SignInWithAppleOperationParams? = nil) -> SignInWithAppleOperationController {
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
        if let params, !(params is SignInWithAppleOperationParams) {
            return .unavailable("Unsupported params type: \(String(describing: type(of: params)))")
        }
        return .available
    }

    private func unexpectedEventError(eventDescription: String, state: SignInWithAppleOperationState) -> SignInWithAppleOperationFailure {
        .unexpected(message: "\(Self.self): Unexpected event [\(eventDescription)] for state [\(state)]")
    }

    private func isAlive() async -> Bool {
        await MainActor.run { if case .completed = self.state { false } else { true } }
    }

    @MainActor
    private func markCompletedIfNeeded(_ result: OperationResult<AccessTokenWithUserInfo, SignInWithAppleOperationFailure>) -> Bool {
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
            await MainActor.run { self.ui.cancel() }
            self.taskRefs.clear([.timeout, .ui])
            await MainActor.run { self.operationRegistry.unregister(id: self.operationID) }
            self.controllerImpl._releaseOwner()
            self.controllerImpl.cancel(reason)
            await self.stream.finish()
        }
    }
}

extension SignInWithAppleOperationImpl {

    internal static func create(resolver: any DIContainerResolver) -> any SignInWithAppleOperation {
        do {
            let resolverWithContext = (resolver as! any DIContainer).withContext("SignInWithAppleOperation") { _ in }
            return SignInWithAppleOperationImpl(
                operationType: .oidcAuthenticationApple,
                operationRegistry: try resolver.getOrThrow(type: (any OperationRegistry).self) as! OperationRegistryImpl,
                ui: try resolver.getOrThrow(type: (any SignInWithAppleUI).self),
                api: try resolverWithContext.getOrThrow(type: (any OIDCAPI).self),
                taskScope: try resolver.getOrThrow(type: TaskScope.self),
                context: resolver.getOrNil(type: Context.self),
                logger: resolver.getOrNil(type: OwnIDLogRouter.self),
                unsatisfiedDependencies: resolver.getUnsatisfiedDependencies(for: (any SignInWithAppleOperation).self)
            )
        } catch {
            return Failed(error: error)
        }
    }
}

private final class Failed: SignInWithAppleOperation, @unchecked Sendable {
    let operationType: OperationType = .oidcAuthenticationApple
    let operationID: OperationID = OperationType.oidcAuthenticationApple.createOperationID()
    let controller: SignInWithAppleOperationController
    private let controllerImpl: OperationControllerImpl<AccessTokenWithUserInfo, SignInWithAppleOperationFailure>
    private let failure: SignInWithAppleOperationFailure

    init(error: any Error) {
        let controller = OperationControllerImpl<AccessTokenWithUserInfo, SignInWithAppleOperationFailure>(operationID: operationID) { _ in
        }
        let failure = SignInWithAppleOperationFailure.unexpected(
            message: String(describing: error),
            underlyingError: error.asSendableError()
        )
        self.failure = failure
        controller.fail(failure)
        self.controllerImpl = controller
        self.controller = controller
    }

    @discardableResult
    func start(params: SignInWithAppleOperationParams? = nil) -> SignInWithAppleOperationController {
        controller
    }

    func availability(params: (any CapabilityParams)?) async -> Availability {
        .unavailable(failure.message)
    }

    @MainActor
    func stateStream() -> AsyncStream<SignInWithAppleOperationState> {
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

extension OIDCStartAPIFailure {
    fileprivate func toAppleOperationFailure() -> SignInWithAppleOperationFailure {
        switch self {
        case .badRequest(.invalidArgument(let errorCode, let message)), .badRequest(.unknown(let errorCode, let message)):
            return .input(.invalidRequest(errorCode: errorCode, message: message, apiFailure: self))
        case .forbidden(let errorCode, let message):
            return .access(.forbidden(errorCode: errorCode, message: message, apiFailure: self))
        case .failedDependency(.providerFailed(let errorCode, let message, _)):
            return .integration(.providerFailed(errorCode: errorCode, message: message, apiFailure: self))
        case .failedDependency(.missingProvider(let errorCode, let message, let capability, _)):
            return .integration(.missingProvider(errorCode: errorCode, message: message, capability: capability, apiFailure: self))
        case .maximumChallengesReached(let errorCode, let message):
            return .challenge(.maximumChallengesReached(errorCode: errorCode, message: message, apiFailure: self))
        case .unexpected(let errorCode, let message, let underlyingError):
            return .unexpected(errorCode: errorCode, message: message, apiFailure: self, underlyingError: underlyingError)
        }
    }
}

extension OIDCCompleteAPIFailure {
    fileprivate func toAppleOperationFailure() -> SignInWithAppleOperationFailure {
        switch self {
        case .badRequest(.invalidArgument(let errorCode, let message)), .badRequest(.unknown(let errorCode, let message)):
            return .input(.invalidRequest(errorCode: errorCode, message: message, apiFailure: self))
        case .badRequest(.invalidChallenge(let errorCode, let message, let challengeID)):
            return .challenge(.invalid(errorCode: errorCode, message: message, challengeID: challengeID, apiFailure: self))
        case .badRequest(.maximumAttemptsReached(let errorCode, let message, let challengeID)):
            return .challenge(.maximumAttemptsReached(errorCode: errorCode, message: message, challengeID: challengeID, apiFailure: self))
        case .forbidden(let errorCode, let message):
            return .access(.forbidden(errorCode: errorCode, message: message, apiFailure: self))
        case .failedDependency(.providerFailed(let errorCode, let message, _)):
            return .integration(.providerFailed(errorCode: errorCode, message: message, apiFailure: self))
        case .failedDependency(.missingProvider(let errorCode, let message, let capability, _)):
            return .integration(.missingProvider(errorCode: errorCode, message: message, capability: capability, apiFailure: self))
        case .unexpected(let errorCode, let message, let underlyingError):
            return .unexpected(errorCode: errorCode, message: message, apiFailure: self, underlyingError: underlyingError)
        }
    }
}
