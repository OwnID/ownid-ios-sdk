import Foundation

/// Runtime for one ``BoostLoginFlow`` run.
///
/// Maintainer invariant: keep this runtime one-shot and preserve the public ``BoostLoginFlow`` result mapping. Source
/// and trace metadata must not affect the developer-facing flow result or ``SessionCreate`` boundary.
internal final class BoostLoginFlowImpl: BoostLoginFlow, @unchecked Sendable {
    private let userRepository: (any UserRepository)?
    private let ownIDOperation: OwnIDOperation
    private let userJourney: (any UserJourney)?
    private let sessionCreate: (any SessionCreate)?
    private let coder: any JSONCoder
    private let taskScope: TaskScope
    private let context: Context?
    private let loginIDValidator: any LoginIDValidator
    private let logger: OwnIDLogRouter?

    private lazy var actor: BoostLoginFlowActor = {
        BoostLoginFlowActor(
            userRepository: self.userRepository,
            ownIDOperation: self.ownIDOperation,
            userJourney: self.userJourney,
            sessionCreate: self.sessionCreate,
            coder: self.coder,
            taskScope: self.taskScope,
            context: self.context,
            loginIDValidator: self.loginIDValidator,
            logger: self.logger,
            onStateChange: { [weak self] newState in
                self?.taskScope.spawn { [weak self] in
                    await self?.handleStateChange(newState)
                }
            }
        )
    }()

    private let controllerLock = NSLock()
    private var controller: FlowController<BoostFlowLoginResponse, BoostLoginFlowFailure>?
    private let completionLock = NSLock()
    private var didComplete = false
    private let activeAbortLock = NSLock()
    private var activeAbort: ((Reason) -> Void)?

    init(
        userRepository: (any UserRepository)? = nil,
        ownIDOperation: OwnIDOperation,
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
    func start(_ context: BoostFlowContext) -> any BoostLoginFlowController {
        let controller = controllerLock.withLock {
            if let controller = self.controller { return controller }
            let newController = FlowController<BoostFlowLoginResponse, BoostLoginFlowFailure>(
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

        activeAbortLock.withLock { activeAbort = nil }
        taskScope.spawn { [actor = self.actor] in
            await actor.send(event: .start(context))
        }
        return controller
    }

    private func handleStateChange(_ newState: BoostLoginFlowActor.State) async {
        guard let controller else { return }

        if case .active(let opController, _) = newState {
            activeAbortLock.withLock {
                activeAbort = { reason in
                    opController.abort(reason: reason)
                }
            }
        }

        if case .completed(let result) = newState {
            completionLock.withLock { didComplete = true }
            activeAbortLock.withLock { activeAbort = nil }
            switch result {
            case .success(let response):
                if let repo = userRepository {
                    let user = User(loginID: response.loginID, authMethod: response.authMethod)
                    await setLastUser(user, in: repo)
                }
                userJourney?.completeFlow(.loggedIn(response.authMethod))
                controller.complete(response)
            case .canceled(let reason):
                userJourney?.completeFlow(
                    .error(
                        errorCode: .aborted,
                        source: "BoostLoginFlowImpl.handleStateChange.canceled",
                        message: "Canceled with reason: \(reason.description)"
                    )
                )
                controller.cancel(reason)
            case .failure(let failure):
                userJourney?.completeFlow(
                    .error(errorCode: failure.errorCode, source: "BoostLoginFlowImpl.handleStateChange.failure", message: failure.message)
                )
                controller.fail(failure)
            }
        }
    }

    private func setLastUser(_ user: User, in repo: any UserRepository) async {
        do {
            try await repo.setLastUser(user)
        } catch is CancellationError {
        } catch {
            logger?.logI(source: self, prefix: "UserRepository.setLastUser", message: "Failed: \(error.localizedDescription)", cause: error)
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
        Task { [userJourney] in
            controller.cancel(reason)
            if shouldComplete {
                userJourney?.completeFlow(
                    .error(
                        errorCode: .aborted,
                        source: "BoostLoginFlowImpl.handleShutdown.canceled",
                        message: "Canceled with reason: \(reason.description)"
                    )
                )
            }
        }
    }

    internal static func create(resolver: any DIContainerResolver, userJourneyOverride: (any UserJourney)? = nil) -> any BoostLoginFlow {
        do {
            return BoostLoginFlowImpl(
                userRepository: resolver.getOrNil(type: (any UserRepository).self),
                ownIDOperation: (resolver as! any DIContainer).opsNamespace.withContext("BoostLoginFlow") { _ in },
                userJourney: userJourneyOverride ?? resolver.getOrNil(type: (any UserJourney).self),
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

private final class Failed: BoostLoginFlow, @unchecked Sendable {
    private let controller: FlowController<BoostFlowLoginResponse, BoostLoginFlowFailure>

    init(error: any Error) {
        controller = FlowController<BoostFlowLoginResponse, BoostLoginFlowFailure>(onUserAborted: { _ in })
        controller.fail(.unexpected(message: error.localizedDescription, underlyingError: error))
    }

    @discardableResult
    func start(_ context: BoostFlowContext) -> any BoostLoginFlowController {
        controller
    }
}

private actor BoostLoginFlowActor {

    enum State: @unchecked Sendable {
        case created
        case active(controller: any OperationController, context: BoostFlowContext)
        case completed(result: FlowResult<BoostFlowLoginResponse, BoostLoginFlowFailure>)
    }

    enum Event: Sendable {
        case start(BoostFlowContext)
        case abort(Reason)
        case opResult(OperationID, OpResult)
        enum OpResult {
            case loginIDCollect(OperationResult<LoginID, LoginIDCollectOperationFailure>)
            case login(OperationResult<LoginResponse, LoginOperationFailure>)
            case passkeyAssertion(OperationResult<AccessToken, PasskeyAssertionOperationFailure>)
            case passkeyAttestation(OperationResult<AttestationResponse, PasskeyAttestationOperationFailure>)
            case passkeyEnroll(OperationResult<Void, PasskeyEnrollOperationFailure>)
            case emailVerification(OperationResult<AccessOrProofToken, EmailVerificationOperationFailure>)
            case phoneVerification(OperationResult<AccessOrProofToken, PhoneVerificationOperationFailure>)
        }
    }

    private var pendingEvents: [OperationID: Event] = [:]
    private var state: State = .created { didSet { onStateChange(state) } }
    private let userRepository: (any UserRepository)?
    private let ownIDOperation: OwnIDOperation
    private let userJourney: (any UserJourney)?
    private let sessionCreate: (any SessionCreate)?
    private let coder: any JSONCoder
    private let taskScope: TaskScope
    private let context: Context?
    private let loginIDValidator: any LoginIDValidator
    private let logger: OwnIDLogRouter?
    private let onStateChange: @Sendable (State) -> Void
    private let eventContinuation: AsyncStream<Event>.Continuation

    init(
        userRepository: (any UserRepository)?,
        ownIDOperation: OwnIDOperation,
        userJourney: (any UserJourney)?,
        sessionCreate: (any SessionCreate)?,
        coder: any JSONCoder,
        taskScope: TaskScope,
        context: Context?,
        loginIDValidator: any LoginIDValidator,
        logger: OwnIDLogRouter?,
        onStateChange: @escaping @Sendable (State) -> Void
    ) {
        self.userRepository = userRepository
        self.ownIDOperation = ownIDOperation
        self.userJourney = userJourney
        self.sessionCreate = sessionCreate
        self.coder = coder
        self.taskScope = taskScope
        self.context = context
        self.loginIDValidator = loginIDValidator
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
                self.state = newState
                // If an operation became active and we buffered its early event, deliver it now
                if case .active(let controller, _) = newState {
                    while let buffered = pendingEvents.removeValue(forKey: controller.operationID) { send(event: buffered) }
                }
                if case .completed = newState { break }
            }
        } catch {
            logger?.logW(source: self, prefix: "runEventLoop", message: "Flow error \(error)", cause: error)
            self.state = .completed(
                result: .failure(.unexpected(message: "Flow error in Boost Login", underlyingError: error))
            )
        }
        eventContinuation.finish()
    }

    private func reduce(_ state: State, with event: Event) async throws -> State {
        switch (state, event) {
        case (.active(let controller, _), .abort(let reason)):
            controller.abort(reason: reason)
            return .completed(result: .canceled(reason))
        case (_, .abort(let reason)):
            if case .completed = state { return state }
            return .completed(result: .canceled(reason))

        case (.created, .start(let context)):
            return try await handleStart(context: context)

        case (.active(let controller, let context), .opResult(let operationID, let result)):
            guard controller.operationID == operationID else {
                // Buffer the event to deliver once the matching controller becomes active
                pendingEvents[operationID] = event
                return state
            }
            switch result {
            case .loginIDCollect(let r): return try await handleLoginIdCollectResult(r, operationID: operationID, context: context)
            case .login(let r): return try await handleLoginResult(r, operationID: operationID, context: context)
            case .passkeyAssertion(let r): return try await handlePasskeyAssertionResult(r, context: context)
            case .passkeyAttestation(let r): return try await handlePasskeyAttestationResult(r, context: context)
            case .passkeyEnroll(let r): return try await handlePasskeyEnrollResult(r, context: context)
            case .emailVerification(let r):
                return try await handleVerificationResult(r, operationID: operationID, type: .emailVerification, context: context)
            case .phoneVerification(let r):
                return try await handleVerificationResult(r, operationID: operationID, type: .phoneNumberVerification, context: context)
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
        await userJourney?.startFlow(name: "login", source: context.source ?? .explicit, traceParent: context.traceParent)
        if let authRequiredResponse = context.authRequiredResponse {
            context.authRequiredResponse = nil
            let controller = OperationControllerImpl<LoginResponse, LoginOperationFailure>(
                operationID: OperationType.sessionCreation.createOperationID()
            ) { _ in }
            await userJourney?.startOperation(operationID: controller.operationID)
            controller.complete(.authRequired(authRequiredResponse))
            taskScope.spawn { [weak self] in
                guard let self else { return }
                let result = await controller.whenSettled()
                await self.completeJourneyOperation(operationID: controller.operationID, result: result)
                await self.send(event: .opResult(controller.operationID, .login(result)))
            }
            return .active(controller: controller, context: context)
        }

        if let resolvedAccessToken = context.accessToken ?? self.context?.accessToken {
            let resolvedLoginID: LoginID
            do {
                resolvedLoginID = try resolvedAccessToken.loginID(coder: coder, validator: loginIDValidator)
            } catch let tokenError {
                let failure = BoostLoginFlowFailure.input(
                    .unresolvedLoginID(
                        errorCode: tokenError.errorCode,
                        message: "LoginID cannot be resolved from access token: \(tokenError.message)",
                        underlyingError: tokenError.asSendableError()
                    )
                )
                return .completed(result: .failure(failure))
            }

            if let missing = ownIDOperation.login.getUnsatisfiedDependencies() {
                let message =
                    missing.isEmpty
                    ? "Login operation unavailable"
                    : "Login operation unavailable. Missing dependencies: \(missing.joined(separator: ", "))"
                return .completed(
                    result: .failure(.operationFailed(operationType: .sessionCreation, errorCode: .integrationError, message: message))
                )
            }

            context.accessToken = resolvedAccessToken
            context.loginID = resolvedLoginID
            context.authMethod = .immediate
            await userJourney?.setUserInfo(resolvedLoginID)

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
                return .active(controller: controller, context: context)
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

        let loginIDCollectOperation = ownIDOperation.withContext("BoostFlow.Login.LoginIDCollectOperation") { builder in
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
            return .active(controller: controller, context: context)
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
                return .active(controller: controller, context: context)
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
        case .success(let response):
            switch response {
            case .success(let successData):
                context.accessToken = successData.accessToken
                context.sessionPayload = successData.sessionPayload
                context.authRequiredResponse = nil

                if let proofToken = context.proofToken, ownIDOperation.passkeys.enroll.canResolve() {
                    let params = PasskeyEnrollOperationParams(
                        proofToken: proofToken,
                        accessToken: successData.accessToken,
                        traceParent: context.traceParent
                    )
                    let operation = ownIDOperation.passkeys.enroll
                    switch await operation.availability(params: params) {
                    case .available:
                        let controller = operation.start(params: params)
                        await userJourney?.startOperation(operationID: controller.operationID)
                        taskScope.spawn { [weak self] in
                            guard let self else { return }
                            let passkeyEnrollOpResult = await controller.whenSettled()
                            await self.completeJourneyOperation(operationID: controller.operationID, result: passkeyEnrollOpResult)
                            await self.send(event: .opResult(controller.operationID, .passkeyEnroll(passkeyEnrollOpResult)))
                        }
                        return .active(controller: controller, context: context)
                    case .unavailable:
                        break
                    }
                }

                guard let loginID = context.loginID else {
                    return .completed(
                        result: .failure(
                            .unexpected(message: "Missing required loginID in login success context")
                        )
                    )
                }

                return .completed(
                    result: await finalizeLoginWithSessionCreate(
                        loginID: loginID,
                        authMethod: context.authMethod ?? .unknown,
                        accessToken: successData.accessToken,
                        sessionPayload: successData.sessionPayload
                    )
                )

            case .accountBlocked(let blocked):
                return .completed(
                    result: .failure(.account(.blocked(errorCode: .userBlocked, message: blocked.reason ?? "Account is blocked")))
                )
            case .accountNotFound(let notFound):
                return .completed(
                    result: .failure(.account(.notFound(errorCode: .userNotFound, message: notFound.reason ?? "Account not found")))
                )

            case .authRequired(let authRequiredResponse):
                context.authRequiredResponse = authRequiredResponse
                context.accessToken = nil
                context.authMethod = nil

                if authRequiredResponse.authRequirements.isTargetScoreAchievable() == false {
                    return .completed(
                        result: .failure(.insufficientAuth(errorCode: .unknown, message: "Target score is not achievable"))
                    )
                }
                return try await selectAndRunNextAuthOperation(context: context)
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

    private func handlePasskeyAssertionResult(
        _ result: OperationResult<AccessToken, PasskeyAssertionOperationFailure>,
        context: BoostFlowContext
    ) async throws -> State {
        var context = context
        switch result {
        case .success(let accessToken):
            context.accessToken = accessToken
            context.authMethod = .passkey
            context.addSucceedOperation(operationType: .passkeyAuth)
            if context.isTargetScoreAchieved() {
                context.authRequiredResponse = nil
                let params = LoginOperationParams(accessToken: accessToken, loginID: nil, traceParent: context.traceParent)
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
                    return .active(controller: controller, context: context)
                case .unavailable(let message):
                    return .completed(
                        result: .failure(.operationFailed(operationType: .sessionCreation, errorCode: .integrationError, message: message))
                    )
                }
            } else {
                return try await selectAndRunNextAuthOperation(context: context)
            }
        case .canceled:
            context.addFailedOperation(operationType: .passkeyAuth)
            context.addFailedOperation(operationType: .passkeyCreation)
            return try await selectAndRunNextAuthOperation(context: context)
        case .failure(let failure):
            context.addFailedOperation(operationType: .passkeyAuth)
            switch failure {
            case .credential(.noApplicablePasskeys):
                break
            default:
                context.addFailedOperation(operationType: .passkeyCreation)
            }
            return try await selectAndRunNextAuthOperation(context: context)
        }
    }

    private func handlePasskeyAttestationResult(
        _ result: OperationResult<AttestationResponse, PasskeyAttestationOperationFailure>,
        context: BoostFlowContext
    ) async throws -> State {
        var context = context
        // Optional passkey creation must not affect auth score, but must not be retried.
        context.addFailedOperation(operationType: .passkeyCreation)
        if case .success(let response) = result {
            context.proofToken = response.proofToken
        }
        return try await selectAndRunNextAuthOperation(context: context)
    }

    private func handlePasskeyEnrollResult(
        _ result: OperationResult<Void, PasskeyEnrollOperationFailure>,
        context: BoostFlowContext
    ) async throws -> State {
        guard let sessionPayload = context.sessionPayload else {
            return .completed(result: .failure(.unexpected(message: "Missing required sessionPayload in login success context")))
        }
        guard let loginID = context.loginID else {
            return .completed(result: .failure(.unexpected(message: "Missing required loginID in login success context")))
        }
        guard let accessToken = context.accessToken else {
            return .completed(result: .failure(.unexpected(message: "Missing required accessToken in login success context")))
        }

        return .completed(
            result: await finalizeLoginWithSessionCreate(
                loginID: loginID,
                authMethod: context.authMethod ?? .unknown,
                accessToken: accessToken,
                sessionPayload: sessionPayload
            )
        )
    }

    private func handleVerificationResult<Failure: OperationFailure>(
        _ result: OperationResult<AccessOrProofToken, Failure>,
        operationID: OperationID,
        type: OperationType,
        context: BoostFlowContext
    ) async throws -> State {
        var context = context
        switch result {
        case .success(let token):
            let accessToken: AccessToken
            switch token {
            case .accessToken(let value):
                accessToken = value
            case .proofToken:
                return .completed(
                    result: .failure(
                        .operationFailed(
                            operationType: type,
                            errorCode: .integrationError,
                            message: "Verification operation returned proofToken, but accessToken is required for Boost Login",
                            operationID: operationID
                        )
                    )
                )
            }

            context.accessToken = accessToken
            context.authMethod = .otp
            context.addSucceedOperation(operationType: type)
            if context.isTargetScoreAchieved() {
                context.authRequiredResponse = nil
                let params = LoginOperationParams(accessToken: accessToken, loginID: nil, traceParent: context.traceParent)
                let operation = ownIDOperation.login
                switch await operation.availability(params: params) {
                case .available:
                    let controller = operation.start(params: params)
                    await userJourney?.startOperation(operationID: controller.operationID)
                    taskScope.spawn { [weak self] in
                        guard let self else { return }
                        let res = await controller.whenSettled()
                        await self.completeJourneyOperation(operationID: controller.operationID, result: res)
                        await self.send(event: .opResult(controller.operationID, .login(res)))
                    }
                    return .active(controller: controller, context: context)
                case .unavailable(let message):
                    return .completed(
                        result: .failure(.operationFailed(operationType: .sessionCreation, errorCode: .integrationError, message: message))
                    )
                }
            } else {
                return try await selectAndRunNextAuthOperation(context: context)
            }
        case .canceled(let reason):
            return .completed(result: .canceled(reason))
        case .failure(let failure):
            return .completed(
                result: .failure(
                    .operationFailed(
                        operationType: type,
                        errorCode: failure.errorCode,
                        message: "Verification operation failed: \(failure.message)",
                        operationID: operationID,
                        operationFailure: failure
                    )
                )
            )
        }
    }

    private func finalizeLoginWithSessionCreate(
        loginID: LoginID,
        authMethod: AuthMethod,
        accessToken: AccessToken,
        sessionPayload: String
    ) async -> FlowResult<BoostFlowLoginResponse, BoostLoginFlowFailure> {
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

    private func selectAndRunNextAuthOperation(context: BoostFlowContext) async throws -> State {
        var context = context
        guard context.authRequiredResponse != nil else {
            return .completed(result: .failure(.insufficientAuth(errorCode: .unknown, message: "No next operation available")))
        }

        let passedOperations = context.requestedOps ?? [:]
        var nextOpTypes = context.getNextOperationType() ?? []

        if passedOperations.keys.contains(.passkeyCreation) {
            nextOpTypes.removeAll { $0 != .emailVerification && $0 != .phoneNumberVerification }
        } else if passedOperations.isEmpty || passedOperations.keys.contains(.passkeyAuth),
            !nextOpTypes.contains(.passkeyAuth),
            !nextOpTypes.contains(.passkeyCreation)
        {
            nextOpTypes.insert(.passkeyCreation, at: 0)
        }

        if nextOpTypes.isEmpty {
            return .completed(result: .failure(.insufficientAuth(errorCode: .unknown, message: "No next operation available")))
        }

        var unavailableReasons: [String] = []

        for opType in nextOpTypes {
            switch opType {
            case .passkeyCreation:
                if let state = await startPasskeyCreationIfAvailable(context: context) { return state }
                context.addFailedOperation(operationType: .passkeyCreation)

            case .passkeyAuth:
                let operation = ownIDOperation.passkeys.auth
                if let missing = operation.getUnsatisfiedDependencies() {
                    unavailableReasons.append(
                        "\(OperationType.passkeyAuth.rawValue): missing dependencies: \(missing.joined(separator: ", "))"
                    )
                    context.addFailedOperation(operationType: .passkeyAuth)
                    return try await selectAndRunNextAuthOperation(context: context)
                } else {
                    let params = PasskeyAssertionOperationParams(
                        loginID: context.loginID,
                        accessToken: context.accessToken,
                        traceParent: context.traceParent
                    )
                    switch await operation.availability(params: params) {
                    case .available:
                        let controller = operation.start(params: params)
                        await userJourney?.startOperation(operationID: controller.operationID)
                        taskScope.spawn { [weak self] in
                            guard let self else { return }
                            let result = await controller.whenSettled()
                            await self.completeJourneyOperation(operationID: controller.operationID, result: result)
                            await self.send(event: .opResult(controller.operationID, .passkeyAssertion(result)))
                        }
                        return .active(controller: controller, context: context)
                    case .unavailable(let message):
                        unavailableReasons.append("\(OperationType.passkeyAuth.rawValue): \(message)")
                        context.addFailedOperation(operationType: .passkeyAuth)
                        return try await selectAndRunNextAuthOperation(context: context)
                    }
                }

            case .emailVerification:
                let operation = ownIDOperation.verifications.email
                if let missing = operation.getUnsatisfiedDependencies() {
                    unavailableReasons.append(
                        "\(OperationType.emailVerification.rawValue): missing dependencies: \(missing.joined(separator: ", "))"
                    )
                    context.addFailedOperation(operationType: .emailVerification)
                } else {
                    let operationRequirement = context.authRequiredResponse?.authRequirements.operations
                        .first(where: { $0.type == .emailVerification })

                    let params = EmailVerificationOperationParams(
                        loginID: context.loginID,
                        loginIDHintID: operationRequirement?.channels?.first?.id,
                        accessToken: context.accessToken,
                        onUIClick: { [userJourney, taskScope = self.taskScope] operationID in
                            taskScope.spawn { await userJourney?.addOperationClick(operationID: operationID) }
                        },
                        traceParent: context.traceParent
                    )
                    switch await operation.availability(params: params) {
                    case .available:
                        let controller = operation.start(params: params)
                        await userJourney?.startOperation(operationID: controller.operationID)
                        taskScope.spawn { [weak self] in
                            guard let self else { return }
                            let verificationOpResult = await controller.whenSettled()
                            await self.completeJourneyOperation(operationID: controller.operationID, result: verificationOpResult)
                            await self.send(event: .opResult(controller.operationID, .emailVerification(verificationOpResult)))
                        }
                        return .active(controller: controller, context: context)
                    case .unavailable(let message):
                        unavailableReasons.append("\(OperationType.emailVerification.rawValue): \(message)")
                        context.addFailedOperation(operationType: .emailVerification)
                    }
                }

            case .phoneNumberVerification:
                let operation = ownIDOperation.verifications.phone
                if let missing = operation.getUnsatisfiedDependencies() {
                    unavailableReasons.append(
                        "\(OperationType.phoneNumberVerification.rawValue): missing dependencies: \(missing.joined(separator: ", "))"
                    )
                    context.addFailedOperation(operationType: .phoneNumberVerification)
                } else {
                    let operationRequirement = context.authRequiredResponse?.authRequirements.operations
                        .first(where: { $0.type == .phoneNumberVerification })

                    let params = PhoneVerificationOperationParams(
                        loginID: context.loginID,
                        loginIDHintID: operationRequirement?.channels?.first?.id,
                        accessToken: context.accessToken,
                        onUIClick: { [userJourney, taskScope = self.taskScope] operationID in
                            taskScope.spawn { await userJourney?.addOperationClick(operationID: operationID) }
                        },
                        traceParent: context.traceParent
                    )
                    switch await operation.availability(params: params) {
                    case .available:
                        let controller = operation.start(params: params)
                        await userJourney?.startOperation(operationID: controller.operationID)
                        taskScope.spawn { [weak self] in
                            guard let self else { return }
                            let verificationOpResult = await controller.whenSettled()
                            await self.completeJourneyOperation(operationID: controller.operationID, result: verificationOpResult)
                            await self.send(event: .opResult(controller.operationID, .phoneVerification(verificationOpResult)))
                        }
                        return .active(controller: controller, context: context)
                    case .unavailable(let message):
                        unavailableReasons.append("\(OperationType.phoneNumberVerification.rawValue): \(message)")
                        context.addFailedOperation(operationType: .phoneNumberVerification)
                    }
                }

            default: break
            }
        }

        let availableOps = nextOpTypes.map { $0.rawValue }.joined(separator: ", ")
        let unavailableDetails = unavailableReasons.isEmpty ? "" : ". Unavailable operations: \(unavailableReasons.joined(separator: "; "))"
        return .completed(
            result: .failure(
                .insufficientAuth(
                    errorCode: .unknown,
                    message: "No operation available in runtime from: [\(availableOps)]\(unavailableDetails)"
                )
            )
        )
    }

    private func startPasskeyCreationIfAvailable(context: BoostFlowContext) async -> State? {
        guard ownIDOperation.passkeys.create.canResolve() else { return nil }

        let params = PasskeyAttestationOperationParams(
            loginID: context.loginID,
            accessToken: context.accessToken,
            traceParent: context.traceParent
        )

        let operation = ownIDOperation.passkeys.create
        switch await operation.availability(params: params) {
        case .available:
            let controller = operation.start(params: params)
            await userJourney?.startOperation(operationID: controller.operationID)
            taskScope.spawn { [weak self] in
                guard let self else { return }
                let result = await controller.whenSettled()
                await self.completeJourneyOperation(operationID: controller.operationID, result: result)
                await self.send(event: .opResult(controller.operationID, .passkeyAttestation(result)))
            }
            return .active(controller: controller, context: context)
        case .unavailable:
            return nil
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
                source: "BoostLoginFlowActor.completeJourneyOperation.canceled",
                message: "Canceled with reason: \(reason.description)"
            )
        case .failure(let failure):
            await self.userJourney?.completeOperation(
                operationID: operationID,
                errorCode: failure.errorCode,
                source: "BoostLoginFlowActor.completeJourneyOperation.failure",
                message: failure.message
            )
        }
    }

}
