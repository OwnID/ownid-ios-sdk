import Foundation

internal final class PasskeyEnrollFlowImpl: PasskeyEnrollFlow, @unchecked Sendable {
    private let ownIDOperation: OwnIDOperation
    private let coder: any JSONCoder
    private let loginIdValidator: any LoginIDValidator
    private let userJourney: (any UserJourney)?
    private let taskScope: TaskScope
    private let context: Context?
    private let logger: OwnIDLogRouter?

    private lazy var actor: PasskeyEnrollFlowActor = {
        PasskeyEnrollFlowActor(
            ownIDOperation: self.ownIDOperation,
            coder: self.coder,
            loginIdValidator: self.loginIdValidator,
            userJourney: self.userJourney,
            taskScope: self.taskScope,
            context: self.context,
            logger: self.logger,
            onStateChange: { [weak self] newState in
                self?.taskScope.spawnOnMain { [weak self] in
                    await self?.handleStateChange(newState)
                }
            }
        )
    }()

    // Invariant: a flow object is a single run; repeated starts expose the same controller and terminal result.
    private let controllerLock = NSLock()
    private var controller: FlowController<PasskeyEnrollFlowResponse, PasskeyEnrollFlowFailure>?
    private let completionLock = NSLock()
    private var didComplete = false
    private let activeAbortLock = NSLock()
    private var activeAbort: ((Reason) -> Void)?

    init(
        ownIDOperation: OwnIDOperation,
        coder: any JSONCoder,
        loginIdValidator: any LoginIDValidator,
        userJourney: (any UserJourney)?,
        taskScope: TaskScope,
        context: Context?,
        logger: OwnIDLogRouter?
    ) {
        self.ownIDOperation = ownIDOperation
        self.coder = coder
        self.loginIdValidator = loginIdValidator
        self.userJourney = userJourney
        self.taskScope = taskScope
        self.context = context
        self.logger = logger

        taskScope.onShutdown { [weak self] in
            self?.handleShutdown()
        }
    }

    deinit {
        taskScope.shutdown()
        logger?.logV(source: self, prefix: #function, message: nil)
    }

    @discardableResult
    func start(_ context: PasskeyEnrollFlowContext? = nil) -> any PasskeyEnrollController {
        let controller = controllerLock.withLock {
            if let controller = self.controller { return controller }
            let newController = FlowController<PasskeyEnrollFlowResponse, PasskeyEnrollFlowFailure>(
                onUserAborted: { [weak self] reason in
                    self?.taskScope.spawn { [weak self] in
                        await self?.actor.send(event: .abort(reason))
                    }
                }
            )
            newController._attachOwner(self)
            self.controller = newController
            return newController
        }

        guard controller._acceptStart() else { return controller }

        let normalized = (context ?? PasskeyEnrollFlowContext()).copy { builder in
            if builder.traceParent == nil { builder.traceParent = TraceContext.generateTraceParent() }
        }
        activeAbortLock.withLock { activeAbort = nil }
        taskScope.spawn { [actor = self.actor] in
            await actor.send(event: .start(normalized))
        }
        return controller
    }

    func availability(params: (any CapabilityParams)?) async -> Availability {
        let flowContext: PasskeyEnrollFlowContext?
        if let params {
            guard let typedParams = params as? PasskeyEnrollFlowContext else {
                return .unavailable("Unsupported params type: \(String(describing: type(of: params)))")
            }
            flowContext = typedParams
        } else {
            flowContext = nil
        }

        let resolvedAccessToken = flowContext?.accessToken ?? self.context?.accessToken
        guard let resolvedAccessToken else {
            return .unavailable("AccessToken is required")
        }

        if let proofToken = flowContext?.proofToken {
            let params = PasskeyEnrollOperationParams(
                proofToken: proofToken,
                accessToken: resolvedAccessToken,
                headless: flowContext?.headless,
                traceParent: flowContext?.traceParent
            )
            return await ownIDOperation.passkeys.enroll.availability(params: params)
        }

        let params = PasskeyAttestationOperationParams(
            loginID: nil,
            accessToken: resolvedAccessToken,
            traceParent: flowContext?.traceParent
        )
        return await ownIDOperation.passkeys.create.availability(params: params)
    }

    @MainActor
    private func handleStateChange(_ newState: PasskeyEnrollFlowActor.State) async {
        guard let controller else { return }

        if case .active(let opController, _, _) = newState {
            activeAbortLock.withLock {
                activeAbort = { reason in
                    opController.abort(reason: reason)
                }
            }
        }

        if case .completed(let result) = newState {
            let shouldComplete = completionLock.withLock {
                if didComplete { return false }
                didComplete = true
                return true
            }
            activeAbortLock.withLock { activeAbort = nil }

            switch result {
            case .success(let response):
                if shouldComplete {
                    userJourney?.completeFlow(.completed(nil))
                }
                controller.complete(response)
            case .canceled(let reason):
                if shouldComplete {
                    userJourney?.completeFlow(
                        .error(
                            errorCode: .aborted,
                            source: "PasskeyEnrollFlowImpl.handleStateChange.canceled",
                            message: "Canceled with reason: \(reason.description)"
                        )
                    )
                }
                controller.cancel(reason)
            case .failure(let failure):
                if shouldComplete {
                    userJourney?.completeFlow(
                        .error(
                            errorCode: failure.errorCode,
                            source: "PasskeyEnrollFlowImpl.handleStateChange.failure",
                            message: failure.message
                        )
                    )
                }
                controller.fail(failure)
            }
        }
    }

    private func handleShutdown() {
        guard let controller else { return }
        let reason = Reason.systemError(details: "Operation canceled")
        let shouldComplete = completionLock.withLock {
            if didComplete { return false }
            didComplete = true
            return true
        }
        let abortAction = activeAbortLock.withLock {
            let action = activeAbort
            activeAbort = nil
            return action
        }
        abortAction?(reason)
        controller.cancel(reason)
        if shouldComplete {
            userJourney?.completeFlow(
                .error(
                    errorCode: .aborted,
                    source: "PasskeyEnrollFlowImpl.handleShutdown.canceled",
                    message: "Canceled with reason: \(reason.description)"
                )
            )
        }
    }

    internal static func create(resolver: any DIContainerResolver) -> any PasskeyEnrollFlow {
        do {
            return PasskeyEnrollFlowImpl(
                ownIDOperation: (resolver as! any DIContainer).opsNamespace.withContext("PasskeyEnrollFlow") { _ in },
                coder: try resolver.getOrThrow(type: (any JSONCoder).self),
                loginIdValidator: try resolver.getOrThrow(type: (any LoginIDValidator).self),
                userJourney: resolver.getOrNil(type: (any UserJourney).self),
                taskScope: try resolver.getOrThrow(type: TaskScope.self),
                context: resolver.getOrNil(type: Context.self),
                logger: resolver.getOrNil(type: OwnIDLogRouter.self)
            )
        } catch {
            return Failed(error: error)
        }
    }
}

private final class Failed: PasskeyEnrollFlow, @unchecked Sendable {
    private let controller: FlowController<PasskeyEnrollFlowResponse, PasskeyEnrollFlowFailure>
    private let failure: PasskeyEnrollFlowFailure

    init(error: any Error) {
        let failure = PasskeyEnrollFlowFailure.unexpected(message: error.localizedDescription, underlyingError: error)
        self.failure = failure
        controller = FlowController<PasskeyEnrollFlowResponse, PasskeyEnrollFlowFailure>(onUserAborted: { _ in })
        controller.fail(failure)
    }

    func availability(params: (any CapabilityParams)?) async -> Availability {
        .unavailable(failure.message)
    }

    @discardableResult
    func start(_ context: PasskeyEnrollFlowContext?) -> any PasskeyEnrollController {
        controller
    }
}

private actor PasskeyEnrollFlowActor {

    enum State: @unchecked Sendable {
        case created
        case active(controller: any OperationController, loginID: LoginID, context: PasskeyEnrollFlowContext)
        case completed(result: FlowResult<PasskeyEnrollFlowResponse, PasskeyEnrollFlowFailure>)
    }

    enum Event: Sendable {
        case start(PasskeyEnrollFlowContext)
        case abort(Reason)
        case attestationResult(OperationID, OperationResult<AttestationResponse, PasskeyAttestationOperationFailure>)
        case enrollResult(OperationID, OperationResult<Void, PasskeyEnrollOperationFailure>)
    }

    private var state: State = .created { didSet { onStateChange(state) } }
    private let ownIDOperation: OwnIDOperation
    private let coder: any JSONCoder
    private let loginIdValidator: any LoginIDValidator
    private let userJourney: (any UserJourney)?
    private let taskScope: TaskScope
    private let context: Context?
    private let logger: OwnIDLogRouter?
    private let onStateChange: @Sendable (State) -> Void
    private let eventContinuation: AsyncStream<Event>.Continuation

    init(
        ownIDOperation: OwnIDOperation,
        coder: any JSONCoder,
        loginIdValidator: any LoginIDValidator,
        userJourney: (any UserJourney)?,
        taskScope: TaskScope,
        context: Context?,
        logger: OwnIDLogRouter?,
        onStateChange: @escaping @Sendable (State) -> Void
    ) {
        self.ownIDOperation = ownIDOperation
        self.coder = coder
        self.loginIdValidator = loginIdValidator
        self.userJourney = userJourney
        self.taskScope = taskScope
        self.context = context
        self.logger = logger
        self.onStateChange = onStateChange

        let (stream, continuation) = AsyncStream.makeStream(of: Event.self)
        self.eventContinuation = continuation

        let loopTask = taskScope.spawn { [weak self] in
            guard let self else { return }
            await self.runEventLoop(for: stream)
        }
        if loopTask == nil {
            continuation.finish()
        }
    }

    func send(event: Event) { eventContinuation.yield(event) }

    private func runEventLoop(for stream: AsyncStream<Event>) async {
        do {
            for await event in stream {
                guard !Task.isCancelled else { break }
                logger?.logV(source: self, prefix: "runEventLoop", message: "Event: \(event)")
                let newState = try await reduce(state, with: event)
                logger?.logV(source: self, prefix: "runEventLoop", message: "New state: \(newState)")
                state = newState
                if case .completed = newState { break }
            }
        } catch {
            logger?.logW(source: self, prefix: "runEventLoop", message: "Flow error \(error)", cause: error)
            state = .completed(
                result: .failure(.unexpected(message: "Flow error in Passkey Enroll", underlyingError: error))
            )
        }
        eventContinuation.finish()
    }

    private func reduce(_ state: State, with event: Event) async throws -> State {
        switch (state, event) {
        case (.active(let controller, _, _), .abort(let reason)):
            controller.abort(reason: reason)
            return .completed(result: .canceled(reason))

        case (_, .abort(let reason)):
            if case .completed = state { return state }
            return .completed(result: .canceled(reason))

        case (.created, .start(let flowContext)):
            return try await handleStart(context: flowContext)

        case (.active(let controller, let loginID, let flowContext), .attestationResult(let operationID, let result)):
            guard controller.operationID == operationID else { return state }
            switch result {
            case .success(let response):
                await userJourney?.completeOperation(operationID: operationID, errorCode: nil, source: nil, message: nil)
                let updated = flowContext.copy { $0.proofToken = response.proofToken }
                return try await startEnroll(flowContext: updated, loginID: loginID, proofToken: response.proofToken)
            case .canceled(let reason):
                await userJourney?.completeOperation(
                    operationID: operationID,
                    errorCode: .aborted,
                    source: "PasskeyEnrollFlowActor.reduce.attestationResult.canceled",
                    message: "Canceled with reason: \(reason.description)"
                )
                return .completed(result: .canceled(reason))
            case .failure(let failure):
                await userJourney?.completeOperation(
                    operationID: operationID,
                    errorCode: failure.errorCode,
                    source: "PasskeyEnrollFlowActor.reduce.attestationResult.failure",
                    message: failure.message
                )
                return .completed(
                    result: .failure(
                        .operationFailed(
                            operationType: .passkeyCreation,
                            errorCode: failure.errorCode,
                            message: "Passkey attestation failed: \(failure.message)",
                            operationID: operationID,
                            operationFailure: failure
                        )
                    )
                )
            }

        case (.active(let controller, let loginID, _), .enrollResult(let operationID, let result)):
            guard controller.operationID == operationID else { return state }
            switch result {
            case .success:
                await userJourney?.completeOperation(operationID: operationID, errorCode: nil, source: nil, message: nil)
                return .completed(result: .success(PasskeyEnrollFlowResponse(loginID: loginID)))
            case .canceled(let reason):
                await userJourney?.completeOperation(
                    operationID: operationID,
                    errorCode: .aborted,
                    source: "PasskeyEnrollFlowActor.reduce.enrollResult.canceled",
                    message: "Canceled with reason: \(reason.description)"
                )
                return .completed(result: .canceled(reason))
            case .failure(let failure):
                await userJourney?.completeOperation(
                    operationID: operationID,
                    errorCode: failure.errorCode,
                    source: "PasskeyEnrollFlowActor.reduce.enrollResult.failure",
                    message: failure.message
                )
                return .completed(
                    result: .failure(
                        .operationFailed(
                            operationType: .passkeyEnrollment,
                            errorCode: failure.errorCode,
                            message: "Passkey enroll failed: \(failure.message)",
                            operationID: operationID,
                            operationFailure: failure
                        )
                    )
                )
            }

        default:
            logger?.logW(source: self, prefix: #function, message: "Unhandled event/state: \(event) | \(state)")
            return state
        }
    }

    private func handleStart(context: PasskeyEnrollFlowContext) async throws -> State {
        await userJourney?.startFlow(name: "headless-passkey-enroll", source: .explicit, traceParent: context.traceParent)

        let resolvedAccessToken = context.accessToken ?? self.context?.accessToken
        guard let resolvedAccessToken else {
            return .completed(
                result: .failure(.input(.missingAccessToken(errorCode: .invalidArgument, message: "AccessToken is required")))
            )
        }

        let loginID: LoginID
        do {
            loginID = try resolvedAccessToken.loginID(coder: coder, validator: loginIdValidator)
        } catch let tokenError {
            let failure = PasskeyEnrollFlowFailure.input(
                .unresolvedLoginID(
                    errorCode: tokenError.errorCode,
                    message: "LoginID cannot be resolved from access token: \(tokenError.message)",
                    underlyingError: tokenError.asSendableError()
                )
            )
            return .completed(result: .failure(failure))
        }

        await userJourney?.setUserInfo(loginID)

        let updatedContext = context.copy { $0.accessToken = resolvedAccessToken }

        if let proofToken = updatedContext.proofToken {
            return try await startEnroll(flowContext: updatedContext, loginID: loginID, proofToken: proofToken)
        }

        if let missing = ownIDOperation.passkeys.create.getUnsatisfiedDependencies() {
            let base = "PasskeyAttestationOperation unavailable"
            let message = missing.isEmpty ? base : "\(base). Missing dependencies: \(missing.joined(separator: ", "))"
            return .completed(
                result: .failure(.operationFailed(operationType: .passkeyCreation, errorCode: .integrationError, message: message))
            )
        }

        let params = PasskeyAttestationOperationParams(
            loginID: nil,
            accessToken: resolvedAccessToken,
            traceParent: updatedContext.traceParent
        )
        let operation = ownIDOperation.passkeys.create
        switch await operation.availability(params: params) {
        case .available:
            let controller = operation.start(params: params)
            await userJourney?.startOperation(operationID: controller.operationID)
            taskScope.spawn { [actor = self, operationID = controller.operationID] in
                let result = await controller.whenSettled()
                await actor.send(event: .attestationResult(operationID, result))
            }
            return .active(controller: controller, loginID: loginID, context: updatedContext)
        case .unavailable(let message):
            return .completed(
                result: .failure(.operationFailed(operationType: .passkeyCreation, errorCode: .integrationError, message: message))
            )
        }
    }

    private func startEnroll(
        flowContext: PasskeyEnrollFlowContext,
        loginID: LoginID,
        proofToken: ProofToken
    ) async throws -> State {
        if let missing = ownIDOperation.passkeys.enroll.getUnsatisfiedDependencies() {
            let base = "PasskeyEnrollOperation unavailable"
            let message = missing.isEmpty ? base : "\(base). Missing dependencies: \(missing.joined(separator: ", "))"
            return .completed(
                result: .failure(.operationFailed(operationType: .passkeyEnrollment, errorCode: .integrationError, message: message))
            )
        }

        let params = PasskeyEnrollOperationParams(
            proofToken: proofToken,
            accessToken: flowContext.accessToken,
            headless: flowContext.headless,
            traceParent: flowContext.traceParent
        )
        let operation = ownIDOperation.passkeys.enroll
        switch await operation.availability(params: params) {
        case .available:
            let controller = operation.start(params: params)
            await userJourney?.startOperation(operationID: controller.operationID)
            taskScope.spawn { [actor = self, operationID = controller.operationID] in
                let result = await controller.whenSettled()
                await actor.send(event: .enrollResult(operationID, result))
            }
            return .active(controller: controller, loginID: loginID, context: flowContext)
        case .unavailable(let message):
            return .completed(
                result: .failure(.operationFailed(operationType: .passkeyEnrollment, errorCode: .integrationError, message: message))
            )
        }
    }
}
