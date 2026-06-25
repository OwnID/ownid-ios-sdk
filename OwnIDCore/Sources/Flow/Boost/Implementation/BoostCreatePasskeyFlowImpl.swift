import Foundation

/// Runtime for one ``BoostCreatePasskeyFlow`` run.
///
/// Maintainer invariant: keep this runtime one-shot and preserve the public ``BoostCreatePasskeyFlow`` result mapping.
/// Source and trace metadata must not affect the developer-facing flow result, proof handoff, or ``SessionCreate``
/// boundary.
internal final class BoostCreatePasskeyFlowImpl: BoostCreatePasskeyFlow, @unchecked Sendable {
    private let userRepository: (any UserRepository)?
    private let ownIDOperation: OwnIDOperation
    private let boostLoginFlow: any BoostLoginFlow
    private let userJourney: (any UserJourney)?
    private let sessionCreate: (any SessionCreate)?
    private let coder: any JSONCoder
    private let taskScope: TaskScope
    private let context: Context?
    private let loginIDValidator: any LoginIDValidator
    private let logger: OwnIDLogRouter?

    private lazy var actor: BoostCreatePasskeyFlowActor = {
        BoostCreatePasskeyFlowActor(
            userRepository: self.userRepository,
            ownIDOperation: self.ownIDOperation,
            boostLoginFlow: self.boostLoginFlow,
            userJourney: self.userJourney,
            sessionCreate: self.sessionCreate,
            coder: self.coder,
            taskScope: self.taskScope,
            context: self.context,
            loginIDValidator: self.loginIDValidator,
            logger: self.logger,
            onLoginFlowStart: { [weak self] in
                guard let self else { return }
                self.loginFlowStartedLock.withLock { self.loginFlowStarted = true }
            },
            onStateChange: { [weak self] newState in
                self?.taskScope.spawn { [weak self] in
                    await self?.handleStateChange(newState)
                }
            }
        )
    }()

    private let controllerLock = NSLock()
    private var controller: FlowController<BoostFlowResponse, BoostCreatePasskeyFlowFailure>?
    private let loginFlowStartedLock = NSLock()
    private var loginFlowStarted = false
    private let completionLock = NSLock()
    private var didComplete = false
    private let activeAbortLock = NSLock()
    private var activeAbort: ((Reason) -> Void)?

    init(
        userRepository: (any UserRepository)? = nil,
        ownIDOperation: OwnIDOperation,
        boostLoginFlow: any BoostLoginFlow,
        userJourney: (any UserJourney)?,
        sessionCreate: (any SessionCreate)?,
        coder: any JSONCoder,
        taskScope: TaskScope,
        context: Context?,
        loginIDValidator: any LoginIDValidator,
        logger: OwnIDLogRouter?
    ) {
        self.userRepository = userRepository
        self.ownIDOperation = ownIDOperation
        self.boostLoginFlow = boostLoginFlow
        self.userJourney = userJourney
        self.sessionCreate = sessionCreate
        self.coder = coder
        self.taskScope = taskScope
        self.context = context
        self.loginIDValidator = loginIDValidator
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
    func start(_ context: BoostFlowContext) -> any BoostCreatePasskeyFlowController {
        let controller = controllerLock.withLock {
            if let controller = self.controller { return controller }
            let newController = FlowController<BoostFlowResponse, BoostCreatePasskeyFlowFailure>(
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

        loginFlowStartedLock.withLock { loginFlowStarted = false }
        activeAbortLock.withLock { activeAbort = nil }
        taskScope.spawn { [actor = self.actor] in
            await actor.send(event: .start(context))
        }

        return controller
    }

    private func handleStateChange(_ newState: BoostCreatePasskeyFlowActor.State) async {
        guard let controller else { return }

        if case .active(let activeController, _) = newState {
            switch activeController {
            case .operation(let opController):
                activeAbortLock.withLock {
                    activeAbort = { reason in
                        opController.abort(reason: reason)
                    }
                }
            case .flow(let childFlow):
                activeAbortLock.withLock {
                    activeAbort = { reason in
                        childFlow.abort(reason: reason)
                    }
                }
                loginFlowStartedLock.withLock { loginFlowStarted = true }
            }
        }

        if case .completed(let result) = newState {
            completionLock.withLock { didComplete = true }
            activeAbortLock.withLock { activeAbort = nil }
            switch result {
            case .success(let response):
                if case .createPasskey(let reg) = response, let repo = userRepository, reg.proofToken != nil {
                    let user = User(loginID: reg.loginID, authMethod: .passkey)
                    await setLastUser(user, in: repo)
                }
                if case .login(let login) = response {
                    let shouldSave = loginFlowStartedLock.withLock { loginFlowStarted == false }
                    if let repo = userRepository, shouldSave {
                        let user = User(loginID: login.loginID, authMethod: login.authMethod)
                        await setLastUser(user, in: repo)
                    }
                }
                switch response {
                case .createPasskey:
                    userJourney?.completeFlow(.registered(nil))
                case .login:
                    if shouldCompleteParentJourney {
                        if case .login(let login) = response {
                            userJourney?.completeFlow(.loggedIn(login.authMethod))
                        }
                    }
                }
                controller.complete(response)
            case .canceled(let reason):
                if shouldCompleteParentJourney {
                    userJourney?.completeFlow(
                        .error(
                            errorCode: .aborted,
                            source: "BoostCreatePasskeyFlowImpl.handleStateChange.canceled",
                            message: "Canceled with reason: \(reason.description)"
                        )
                    )
                }
                controller.cancel(reason)
            case .failure(let failure):
                if shouldCompleteParentJourney {
                    userJourney?.completeFlow(
                        .error(
                            errorCode: failure.errorCode,
                            source: "BoostCreatePasskeyFlowImpl.handleStateChange.failure",
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
        let shouldCompleteParentJourney = shouldCompleteParentJourney
        Task { [userJourney] in
            controller.cancel(reason)
            if shouldComplete && shouldCompleteParentJourney {
                userJourney?.completeFlow(
                    .error(
                        errorCode: .aborted,
                        source: "BoostCreatePasskeyFlowImpl.handleShutdown.canceled",
                        message: "Canceled with reason: \(reason.description)"
                    )
                )
            }
        }
    }

    private var shouldCompleteParentJourney: Bool {
        loginFlowStartedLock.withLock { loginFlowStarted == false }
    }

    private func setLastUser(_ user: User, in repo: any UserRepository) async {
        do {
            try await repo.setLastUser(user)
        } catch is CancellationError {
        } catch {
            logger?.logI(source: self, prefix: "UserRepository.setLastUser", message: "Failed: \(error.localizedDescription)", cause: error)
        }
    }

    internal static func create(resolver: any DIContainerResolver) -> any BoostCreatePasskeyFlow {
        do {
            let sharedJourney = resolver.getOrNil(type: (any UserJourney).self)
            return BoostCreatePasskeyFlowImpl(
                userRepository: resolver.getOrNil(type: (any UserRepository).self),
                ownIDOperation: (resolver as! any DIContainer).opsNamespace.withContext("BoostCreatePasskeyFlow") { _ in },
                boostLoginFlow: BoostLoginFlowImpl.create(resolver: resolver, userJourneyOverride: sharedJourney),
                userJourney: sharedJourney,
                sessionCreate: resolver.getOrNil(type: (any SessionCreate).self),
                coder: try resolver.getOrThrow(type: (any JSONCoder).self),
                taskScope: try resolver.getOrThrow(type: TaskScope.self),
                context: resolver.getOrNil(type: Context.self),
                loginIDValidator: try resolver.getOrThrow(type: (any LoginIDValidator).self),
                logger: resolver.getOrNil(type: OwnIDLogRouter.self)
            )
        } catch {
            return Failed(error: error)
        }
    }

}

private final class Failed: BoostCreatePasskeyFlow, @unchecked Sendable {
    private let controller: FlowController<BoostFlowResponse, BoostCreatePasskeyFlowFailure>

    init(error: any Error) {
        controller = FlowController<BoostFlowResponse, BoostCreatePasskeyFlowFailure>(onUserAborted: { _ in })
        controller.fail(.unexpected(message: error.localizedDescription, underlyingError: error))
    }

    @discardableResult
    func start(_ context: BoostFlowContext) -> any BoostCreatePasskeyFlowController {
        controller
    }
}

private enum ActiveController: @unchecked Sendable {
    case operation(any OperationController)
    case flow(any BoostLoginFlowController)
}

private actor BoostCreatePasskeyFlowActor {
    enum State: @unchecked Sendable {
        case created
        case active(controller: ActiveController, context: BoostFlowContext)
        case completed(result: FlowResult<BoostFlowResponse, BoostCreatePasskeyFlowFailure>)
    }
    enum Event: Sendable {
        case start(BoostFlowContext)
        case abort(Reason)
        case loginFlowResult(FlowResult<BoostFlowLoginResponse, BoostLoginFlowFailure>)
        case opResult(OperationID, OpResult)
        enum OpResult {
            case loginIDCollect(OperationResult<LoginID, LoginIDCollectOperationFailure>)
            case login(OperationResult<LoginResponse, LoginOperationFailure>)
            case passkeyAttestation(OperationResult<AttestationResponse, PasskeyAttestationOperationFailure>)
        }
    }

    private var pendingEvents: [OperationID: Event] = [:]
    private var state: State = .created { didSet { onStateChange(state) } }
    private let userRepository: (any UserRepository)?
    private let ownIDOperation: OwnIDOperation
    private let boostLoginFlow: any BoostLoginFlow
    private let userJourney: (any UserJourney)?
    private let sessionCreate: (any SessionCreate)?
    private let coder: any JSONCoder
    private let taskScope: TaskScope
    private let context: Context?
    private let loginIDValidator: any LoginIDValidator
    private let logger: OwnIDLogRouter?
    private let onLoginFlowStart: @Sendable () -> Void
    private let onStateChange: @Sendable (State) -> Void
    private let eventContinuation: AsyncStream<Event>.Continuation

    init(
        userRepository: (any UserRepository)?,
        ownIDOperation: OwnIDOperation,
        boostLoginFlow: any BoostLoginFlow,
        userJourney: (any UserJourney)?,
        sessionCreate: (any SessionCreate)?,
        coder: any JSONCoder,
        taskScope: TaskScope,
        context: Context?,
        loginIDValidator: any LoginIDValidator,
        logger: OwnIDLogRouter?,
        onLoginFlowStart: @escaping @Sendable () -> Void,
        onStateChange: @escaping @Sendable (State) -> Void
    ) {
        self.userRepository = userRepository
        self.ownIDOperation = ownIDOperation
        self.boostLoginFlow = boostLoginFlow
        self.userJourney = userJourney
        self.sessionCreate = sessionCreate
        self.coder = coder
        self.taskScope = taskScope
        self.context = context
        self.loginIDValidator = loginIDValidator
        self.logger = logger
        self.onLoginFlowStart = onLoginFlowStart
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

    deinit { logger?.logV(source: self, prefix: #function, message: nil) }

    func send(event: Event) { eventContinuation.yield(event) }

    private func runEventLoop(for stream: AsyncStream<Event>) async {
        do {
            for await event in stream {
                guard !Task.isCancelled else { break }
                logger?.logV(source: self, prefix: "runEventLoop", message: "Event: \(event)")
                let newState = try await reduce(state, with: event)
                logger?.logV(source: self, prefix: "runEventLoop", message: "New state: \(newState)")
                self.state = newState
                // If an operation became active and we buffered its early result, deliver it now
                if case .active(let controller, _) = newState, case .operation(let opController) = controller {
                    let operationID = opController.operationID
                    while let buffered = pendingEvents.removeValue(forKey: operationID) {
                        send(event: buffered)
                    }
                }
                if case .completed = newState { break }
            }
        } catch {
            logger?.logW(source: self, prefix: "runEventLoop", message: "Flow error \(error)", cause: error)
            self.state = .completed(
                result: .failure(.unexpected(message: "Flow error in Boost Create Passkey", underlyingError: error))
            )
        }
        eventContinuation.finish()
    }

    private func reduce(_ state: State, with event: Event) async throws -> State {
        switch (state, event) {
        case (.active(let controller, _), .abort(let reason)):
            switch controller {
            case .operation(let opController): opController.abort(reason: reason)
            case .flow(let flowController): flowController.abort(reason: reason)
            }
            return .completed(result: .canceled(reason))
        case (_, .abort(let reason)):
            if case .completed = state { return state }
            return .completed(result: .canceled(reason))

        case (.created, .start(let context)):
            return try await handleStart(context: context)

        case (.active, .loginFlowResult(let result)):
            switch result {
            case .success(let response): return .completed(result: .success(.login(response)))
            case .canceled(let reason): return .completed(result: .canceled(reason))
            case .failure(let flowError): return .completed(result: .failure(flowError.toCreatePasskeyFlowFailure()))
            }

        case (.active(let controller, let context), .opResult(let operationID, let opResult)):
            guard case .operation(let opController) = controller, opController.operationID == operationID
            else {
                pendingEvents[operationID] = event
                return state
            }
            switch opResult {
            case .loginIDCollect(let result):
                return try await handleLoginIdCollectResult(result, operationID: operationID, context: context)
            case .login(let result): return try await handleLoginResult(result, operationID: operationID, context: context)
            case .passkeyAttestation(let result): return try await handlePasskeyAttestationResult(result, context: context)
            }

        // Buffer early op results that arrive before activation finishes
        case (_, .opResult(let operationID, _)):
            pendingEvents[operationID] = event
            return state

        default:
            logger?.logW(source: self, prefix: #function, message: "Unhandled event/state: \(event) | \(state)")
            return state
        }
    }

    private func handleStart(context: BoostFlowContext) async throws -> State {
        var context = context
        if context.traceParent == nil { context.traceParent = TraceContext.generateTraceParent() }
        await userJourney?.startFlow(
            name: "create-passkey",
            source: context.source ?? .explicit,
            traceParent: context.traceParent
        )
        if let resolvedAccessToken = context.accessToken ?? self.context?.accessToken {
            let resolvedLoginID: LoginID
            do {
                resolvedLoginID = try resolvedAccessToken.loginID(coder: coder, validator: loginIDValidator)
            } catch let tokenError {
                let failure = BoostCreatePasskeyFlowFailure.input(
                    .unresolvedLoginID(
                        errorCode: tokenError.errorCode,
                        message: "LoginID cannot be resolved from access token: \(tokenError.message)",
                        underlyingError: tokenError.asSendableError()
                    )
                )
                return .completed(result: .failure(failure))
            }

            context.accessToken = resolvedAccessToken
            context.loginID = resolvedLoginID
            await userJourney?.setUserInfo(resolvedLoginID)

            if let missing = ownIDOperation.login.getUnsatisfiedDependencies() {
                let message =
                    missing.isEmpty
                    ? "Login operation unavailable"
                    : "Login operation unavailable. Missing dependencies: \(missing.joined(separator: ", "))"
                return .completed(
                    result: .failure(.operationFailed(operationType: .sessionCreation, errorCode: .integrationError, message: message))
                )
            }

            let params = LoginOperationParams(accessToken: resolvedAccessToken, traceParent: context.traceParent)
            let operation = ownIDOperation.login
            switch await operation.availability(params: params) {
            case .available:
                let controller = operation.start(params: params)
                await userJourney?.startOperation(operationID: controller.operationID)
                taskScope.spawn { [weak self] in
                    guard let self else { return }
                    let loginOpResult = await controller.whenSettled()
                    await self.completeJourneyOperation(operationID: controller.operationID, result: loginOpResult)
                    await self.send(event: .opResult(controller.operationID, .login(loginOpResult)))
                }
                return .active(controller: .operation(controller), context: context)
            case .unavailable(let message):
                return .completed(
                    result: .failure(.operationFailed(operationType: .sessionCreation, errorCode: .integrationError, message: message))
                )
            }
        }

        if context.loginID == nil, context.rawLoginID == nil {
            if let loginID = self.context?.loginID {
                context.loginID = loginID
            } else if let rawLoginID = self.context?.rawLoginID {
                context.rawLoginID = rawLoginID
            }
        }

        if context.ignoreLastUser != true, context.loginID == nil, context.rawLoginID == nil, let repo = userRepository {
            do {
                if let lastUserLoginID = try await repo.lastUser()?.loginID {
                    context.loginID = lastUserLoginID
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                logger?.logI(
                    source: self,
                    prefix: "UserRepository.lastUser",
                    message: "Failed: \(error.localizedDescription)",
                    cause: error
                )
            }
        }

        let loginIDCollectOperation = ownIDOperation.withContext("BoostFlow.CreatePasskey.LoginIDCollectOperation") { builder in
            if let loginID = context.loginID {
                builder.authz = .start(loginID)
            } else if let rawLoginID = context.rawLoginID {
                builder.authz = .start(rawLoginID)
            }
        }.loginID.collect

        if let missing = loginIDCollectOperation.getUnsatisfiedDependencies() {
            let message =
                missing.isEmpty
                ? "LoginIdCollect operation unavailable"
                : "LoginIdCollect operation unavailable. Missing dependencies: \(missing.joined(separator: ", "))"
            return .completed(
                result: .failure(.operationFailed(operationType: .loginIDCollect, errorCode: .integrationError, message: message))
            )
        }

        let params = LoginIDCollectOperationParams(
            onUIClick: { [userJourney, taskScope = self.taskScope] operationID in
                taskScope.spawn { await userJourney?.addOperationClick(operationID: operationID) }
            }
        )
        switch await loginIDCollectOperation.availability(params: params) {
        case .available:
            let controller = loginIDCollectOperation.start(params: params)
            await userJourney?.startOperation(operationID: controller.operationID)
            taskScope.spawn { [weak self] in
                guard let self else { return }
                let loginIdCollectOpResult = await controller.whenSettled()
                await self.completeJourneyOperation(operationID: controller.operationID, result: loginIdCollectOpResult)
                await self.send(event: .opResult(controller.operationID, .loginIDCollect(loginIdCollectOpResult)))
            }
            return .active(controller: .operation(controller), context: context)
        case .unavailable(let message):
            return .completed(
                result: .failure(.operationFailed(operationType: .loginIDCollect, errorCode: .integrationError, message: message))
            )
        }
    }

    private func handleLoginIdCollectResult(
        _ result: OperationResult<LoginID, LoginIDCollectOperationFailure>,
        operationID: OperationID,
        context: BoostFlowContext
    ) async throws -> State {
        var context = context
        switch result {
        case .success(let loginID):
            if let missing = ownIDOperation.login.getUnsatisfiedDependencies() {
                let message =
                    missing.isEmpty
                    ? "Login operation unavailable"
                    : "Login operation unavailable. Missing dependencies: \(missing.joined(separator: ", "))"
                return .completed(
                    result: .failure(.operationFailed(operationType: .sessionCreation, errorCode: .integrationError, message: message))
                )
            }
            context.loginID = loginID
            context.authMethod = .immediate
            await userJourney?.setUserInfo(loginID)
            let params = LoginOperationParams(accessToken: context.accessToken, loginID: loginID, traceParent: context.traceParent)
            let operation = ownIDOperation.login
            switch await operation.availability(params: params) {
            case .available:
                let controller = operation.start(params: params)
                await userJourney?.startOperation(operationID: controller.operationID)
                taskScope.spawn { [weak self] in
                    guard let self else { return }
                    let loginOpResult = await controller.whenSettled()
                    await self.completeJourneyOperation(operationID: controller.operationID, result: loginOpResult)
                    await self.send(event: .opResult(controller.operationID, .login(loginOpResult)))
                }
                return .active(controller: .operation(controller), context: context)
            case .unavailable(let message):
                return .completed(
                    result: .failure(.operationFailed(operationType: .sessionCreation, errorCode: .integrationError, message: message))
                )
            }
        case .canceled(let reason):
            return .completed(result: .canceled(reason))
        case .failure(let failure):
            return .completed(
                result: .failure(
                    .operationFailed(
                        operationType: .loginIDCollect,
                        errorCode: failure.errorCode,
                        message: "LoginIdCollect operation failed: \(failure.message)",
                        operationID: operationID,
                        operationFailure: failure
                    )
                )
            )
        }
    }

    private func handleLoginResult(
        _ result: OperationResult<LoginResponse, LoginOperationFailure>,
        operationID: OperationID,
        context: BoostFlowContext
    ) async throws -> State {
        var context = context
        switch result {
        case .success(let loginResponse):
            switch loginResponse {
            case .success(let successData):
                guard let loginID = context.loginID else {
                    return .completed(
                        result: .failure(
                            .unexpected(
                                errorCode: .invalidArgument,
                                message: "LoginID is required for create-passkey login success context"
                            )
                        )
                    )
                }

                let loginResult = await finalizeLoginWithSessionCreate(
                    loginID: loginID,
                    authMethod: .immediate,
                    accessToken: successData.accessToken,
                    sessionPayload: successData.sessionPayload
                )

                switch loginResult {
                case .success(let response):
                    return .completed(result: .success(.login(response)))
                case .canceled(let reason):
                    return .completed(result: .canceled(reason))
                case .failure(let failure):
                    return .completed(result: .failure(failure))
                }

            case .accountBlocked(let blocked):
                return .completed(
                    result: .failure(.account(.blocked(errorCode: .userBlocked, message: blocked.reason ?? "Account is blocked")))
                )

            case .accountNotFound:
                context.accessToken = nil
                context.authRequiredResponse = nil
                return try await startPasskeyAttestation(context: context)

            case .authRequired(let authRequiredResponse):
                context.authRequiredResponse = authRequiredResponse
                context.accessToken = nil
                context.authMethod = nil

                let hasPasskeyAuth = authRequiredResponse.authRequirements.operations.contains { $0.type == .passkeyAuth }
                if hasPasskeyAuth {
                    onLoginFlowStart()
                    await userJourney?.switchToFlow(flowID: nil, name: "login", source: context.source ?? .explicit)
                    let loginFlowController = boostLoginFlow.start(context)
                    let forward: @Sendable () async -> Void = { [actor = self, controller = loginFlowController] in
                        let res = await controller.whenSettled()
                        await actor.send(event: .loginFlowResult(res))
                    }
                    taskScope.spawn {
                        await forward()
                    }
                    return .active(controller: .flow(loginFlowController), context: context)
                }
                return try await startPasskeyAttestation(context: context)
            }
        case .canceled(let reason):
            return .completed(result: .canceled(reason))
        case .failure(let failure):
            return .completed(
                result: .failure(
                    .operationFailed(
                        operationType: .sessionCreation,
                        errorCode: failure.errorCode,
                        message: "Login operation failed: \(failure.message)",
                        operationID: operationID,
                        operationFailure: failure
                    )
                )
            )
        }
    }

    private func handlePasskeyAttestationResult(
        _ result: OperationResult<AttestationResponse, PasskeyAttestationOperationFailure>,
        context: BoostFlowContext
    ) async throws -> State {
        guard let loginID = context.loginID else {
            return .completed(
                result: .failure(
                    .unexpected(errorCode: .invalidArgument, message: "LoginID is required for create-passkey response")
                )
            )
        }

        switch result {
        case .success(let response):
            let createPasskeyResponse = BoostFlowCreatePasskeyResponse(
                loginID: loginID,
                proofToken: response.proofToken,
                ownIdData: response.ownIdData
            )
            return .completed(result: .success(.createPasskey(createPasskeyResponse)))
        case .canceled(let reason):
            return .completed(result: .canceled(reason))
        case .failure:
            let createPasskeyResponse = BoostFlowCreatePasskeyResponse(
                loginID: loginID,
                proofToken: nil,
                ownIdData: nil
            )
            return .completed(result: .success(.createPasskey(createPasskeyResponse)))
        }
    }

    private func startPasskeyAttestation(context: BoostFlowContext) async throws -> State {
        let context = context
        let operationID = OperationType.passkeyCreation.createOperationID()
        if let missing = ownIDOperation.passkeys.create.getUnsatisfiedDependencies() {
            let message =
                missing.isEmpty
                ? "PasskeyAttestationOperation unavailable"
                : "PasskeyAttestationOperation unavailable. Missing dependencies: \(missing.joined(separator: ", "))"
            let controller = OperationControllerImpl<AttestationResponse, PasskeyAttestationOperationFailure>(operationID: operationID) {
                _ in
            }
            controller.fail(.unexpected(errorCode: .integrationError, message: message))
            await userJourney?.startOperation(operationID: controller.operationID)
            taskScope.spawn { [weak self] in
                guard let self else { return }
                let attestationResponse = await controller.whenSettled()
                await self.completeJourneyOperation(operationID: controller.operationID, result: attestationResponse)
                await self.send(event: .opResult(controller.operationID, .passkeyAttestation(attestationResponse)))
            }
            return .active(controller: .operation(controller), context: context)
        }

        let params = PasskeyAttestationOperationParams(
            loginID: context.loginID,
            accessToken: nil,
            traceParent: context.traceParent
        )
        let operation = ownIDOperation.passkeys.create
        switch await operation.availability(params: params) {
        case .available:
            let controller = operation.start(params: params)
            await userJourney?.startOperation(operationID: controller.operationID)
            taskScope.spawn { [weak self] in
                guard let self else { return }
                let attestationResponse = await controller.whenSettled()
                await self.completeJourneyOperation(operationID: controller.operationID, result: attestationResponse)
                await self.send(event: .opResult(controller.operationID, .passkeyAttestation(attestationResponse)))
            }
            return .active(controller: .operation(controller), context: context)
        case .unavailable(let message):
            let controller = OperationControllerImpl<AttestationResponse, PasskeyAttestationOperationFailure>(operationID: operationID) {
                _ in
            }
            controller.fail(.unexpected(errorCode: .integrationError, message: message))
            await userJourney?.startOperation(operationID: controller.operationID)
            taskScope.spawn { [weak self] in
                guard let self else { return }
                let attestationResponse = await controller.whenSettled()
                await self.completeJourneyOperation(operationID: controller.operationID, result: attestationResponse)
                await self.send(event: .opResult(controller.operationID, .passkeyAttestation(attestationResponse)))
            }
            return .active(controller: .operation(controller), context: context)
        }
    }

    private func finalizeLoginWithSessionCreate(
        loginID: LoginID,
        authMethod: AuthMethod,
        accessToken: AccessToken,
        sessionPayload: String
    ) async -> FlowResult<BoostFlowLoginResponse, BoostCreatePasskeyFlowFailure> {
        let baseResponse = BoostFlowLoginResponse(
            loginID: loginID,
            authMethod: authMethod,
            accessToken: accessToken,
            sessionPayload: sessionPayload,
            session: nil
        )

        guard let sessionCreate else {
            return .success(baseResponse)
        }

        let params = SessionCreateParams(
            loginID: loginID,
            accessToken: accessToken,
            authMethod: authMethod,
            sessionPayload: sessionPayload
        )
        guard await sessionCreate.isAvailable(params: params) else {
            return .success(baseResponse)
        }

        let sessionCreateResult = await sessionCreate.create(params: params)

        switch sessionCreateResult {
        case .success(let sessionOutput):
            return .success(
                BoostFlowLoginResponse(
                    loginID: loginID,
                    authMethod: authMethod,
                    accessToken: accessToken,
                    sessionPayload: sessionPayload,
                    session: sessionOutput.session
                )
            )
        case .failure(let error):
            if error is CancellationError {
                return .canceled(.systemError(details: "Session creation canceled"))
            }
            return .failure(
                .sessionCreationFailed(
                    errorCode: .integrationError,
                    message: "Session creation failed: \(error.localizedDescription)",
                    underlyingError: error
                )
            )
        }
    }

    private func completeJourneyOperation<R, Failure>(operationID: OperationID, result: OperationResult<R, Failure>) async
    where Failure: OperationFailure {
        switch result {
        case .success:
            await self.userJourney?.completeOperation(operationID: operationID, errorCode: nil, source: nil, message: nil)
        case .canceled(let reason):
            await self.userJourney?.completeOperation(
                operationID: operationID,
                errorCode: .aborted,
                source: "BoostCreatePasskeyFlowActor.completeJourneyOperation.canceled",
                message: "Canceled with reason: \(reason.description)"
            )
        case .failure(let failure):
            await self.userJourney?.completeOperation(
                operationID: operationID,
                errorCode: failure.errorCode,
                source: "BoostCreatePasskeyFlowActor.completeJourneyOperation.failure",
                message: failure.message
            )
        }
    }

}

extension BoostLoginFlowFailure {
    fileprivate func toCreatePasskeyFlowFailure() -> BoostCreatePasskeyFlowFailure {
        switch self {
        case .input(.unresolvedLoginID(let errorCode, let message, let underlyingError)):
            return .input(.unresolvedLoginID(errorCode: errorCode, message: message, underlyingError: underlyingError))
        case .account(.blocked(let errorCode, let message)):
            return .account(.blocked(errorCode: errorCode, message: message))
        case .account(.notFound(let errorCode, let message)):
            return .account(.notFound(errorCode: errorCode, message: message))
        case .insufficientAuth(let errorCode, let message):
            return .insufficientAuth(errorCode: errorCode, message: message)
        case .sessionCreationFailed(let errorCode, let message, let underlyingError):
            return .sessionCreationFailed(errorCode: errorCode, message: message, underlyingError: underlyingError)
        case .operationFailed(let operationType, let errorCode, let message, let operationID, let operationFailure, let underlyingError):
            return .operationFailed(
                operationType: operationType,
                errorCode: errorCode,
                message: message,
                operationID: operationID,
                operationFailure: operationFailure,
                underlyingError: underlyingError
            )
        case .unexpected(let errorCode, let message, let underlyingError):
            return .unexpected(errorCode: errorCode, message: message, underlyingError: underlyingError)
        }
    }
}
