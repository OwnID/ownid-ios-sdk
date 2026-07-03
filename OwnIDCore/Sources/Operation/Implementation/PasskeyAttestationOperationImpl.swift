import Foundation

/// Instance-scoped runtime for one ``PasskeyAttestationOperation`` lifecycle.
///
/// The namespace entry creates a fresh runtime for each launch. This runtime registers its controller while the operation
/// can be presented by SDK UI hosts, owns passkey/API side effects for that run, and unregisters after the controller
/// settles or cleanup completes. Abort requests are operation-owned cancellation inputs; callers must observe settlement
/// through the controller.
internal final class PasskeyAttestationOperationImpl: PasskeyAttestationOperation, @unchecked Sendable {
    enum Event: Sendable {
        case start(PasskeyAttestationOperationParams?)
        case ui(PasskeyResult<AttestationResult>)
        case abort(Reason)
        case complete(OperationResult<AttestationResponse, PasskeyAttestationOperationFailure>)
    }

    internal let operationType: OperationType
    internal let operationID: OperationID
    private let operationRegistry: OperationRegistryImpl
    private let ui: any PasskeyAttestationUI
    private let api: any PasskeyAttestationAPI
    private let taskScope: TaskScope
    private let context: Context?
    private let loginIDValidator: (any LoginIDValidator)?
    private let logger: OwnIDLogRouter?
    private let unsatisfiedDependencies: [String]?

    @MainActor @BroadcastedState private var state: PasskeyAttestationOperationState = .created
    @MainActor internal func stateStream() -> AsyncStream<PasskeyAttestationOperationState> { _state.stream() }

    private let stream = OperationEventStream<Event>()
    private enum TaskRefKey { case timeout, ui }
    private let taskRefs = OperationTaskRefs<TaskRefKey>()

    private lazy var controllerImpl: OperationControllerImpl<AttestationResponse, PasskeyAttestationOperationFailure> = {
        let controller = OperationControllerImpl<AttestationResponse, PasskeyAttestationOperationFailure>(operationID: operationID) {
            [weak self] reason in
            guard let self else { return }
            taskScope.spawn { await self.stream.yield(.abort(reason)) }
        }
        controller._attachOwner(self)
        return controller
    }()

    internal var controller: PasskeyAttestationOperationController { controllerImpl }

    internal init(
        operationType: OperationType,
        operationRegistry: OperationRegistryImpl,
        ui: any PasskeyAttestationUI,
        api: any PasskeyAttestationAPI,
        taskScope: TaskScope,
        context: Context?,
        loginIDValidator: (any LoginIDValidator)?,
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
        self.loginIDValidator = loginIDValidator
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
                            let params = params ?? PasskeyAttestationOperationParams()
                            let accessToken = params.accessToken ?? self.context?.accessToken
                            var loginID: LoginID?
                            if let provided = params.loginID {
                                loginID = provided
                            } else {
                                do {
                                    loginID = try self.context?.loginID(loginIDValidator: self.loginIDValidator)
                                } catch let error {
                                    if accessToken == nil {
                                        let failure = (error as! LoginIDResolutionError).toPasskeyAttestationOperationFailure()
                                        guard await self.isAlive() else { return }
                                        await self.stream.yield(.complete(.failure(failure)))
                                        return
                                    }
                                }
                            }
                            if loginID == nil && accessToken == nil {
                                guard await self.isAlive() else { return }
                                await self.stream.yield(
                                    .complete(
                                        .failure(
                                            PasskeyAttestationOperationFailure.input(
                                                .missingLoginIDOrAccessToken(
                                                    errorCode: .invalidArgument,
                                                    message: "LoginID or AccessToken required"
                                                )
                                            )
                                        )
                                    )
                                )
                                return
                            }

                            let apiResult = await self.api.start(
                                params: PasskeyAttestationAPIParams(
                                    loginID: loginID,
                                    accessToken: accessToken,
                                    traceParent: params.traceParent ?? TraceContext.generateTraceParent()
                                )
                            )
                            switch apiResult {
                            case .success(let apiController):
                                guard await self.isAlive() else { return }
                                if let timeout = apiController.attestationOptions.timeout {
                                    self.taskRefs.replace(
                                        .timeout,
                                        with: taskScope.spawn { [weak self] in
                                            guard let self else { return }
                                            do {
                                                let nanos = UInt64(timeout.milliseconds) * 1_000_000 + 2_000_000_000
                                                try await Task.sleep(nanoseconds: nanos)
                                                await self.stream.yield(.abort(.timeout))
                                            } catch {}
                                        }
                                    )
                                }
                                await MainActor.run { self.state = .active(apiController: apiController) }

                                let ui = self.ui
                                self.taskRefs.replace(
                                    .ui,
                                    with: taskScope.spawnOnMain { [weak self] in
                                        guard let self else { return }
                                        guard await self.isAlive() else { return }
                                        let attestationResult = await ui.createCredential(options: apiController.attestationOptions)
                                        await self.stream.yield(.ui(attestationResult))
                                    }
                                )
                            case .failure(let apiError):
                                self.logger?.logI(
                                    source: self,
                                    prefix: "Event.Start",
                                    message: "API start failed: \(apiError.message)"
                                )
                                await self.stream.yield(.complete(.failure(apiError.toOperationFailure())))
                            case .canceled:
                                guard await self.isAlive() else { return }
                                await self.stream.yield(.complete(.canceled(.systemError(details: "Operation canceled"))))
                            }
                        }
                    }

                case .ui(let attestationResult):
                    let state = await MainActor.run { self.state }
                    switch state {
                    case .created, .preparing:
                        let error = self.unexpectedEventError(eventDescription: ".ui", state: state)
                        await self.stream.yield(.complete(.failure(error)))
                    case .active(let apiController):
                        switch attestationResult {
                        case .success(let attestation):
                            taskScope.spawn { [weak self] in
                                guard let self else { return }
                                let verifyResult = await apiController.verify(attestationResult: attestation)
                                guard await self.isAlive() else { return }
                                await self.stream.yield(
                                    .complete(
                                        verifyResult.fold(
                                            onSuccess: OperationResult.success,
                                            onError: { apiError in .failure(apiError.toOperationFailure()) },
                                            onCanceled: { .canceled(.systemError(details: "Operation canceled")) }
                                        )
                                    )
                                )
                            }
                        case .canceled(let reason):
                            taskScope.spawn { [weak self] in
                                guard let self else { return }
                                _ = await apiController.cancel(reason: reason)
                                await self.stream.yield(.complete(.canceled(reason)))
                            }
                        case .failure(let passkeyError):
                            taskScope.spawn { [weak self] in
                                guard let self else { return }
                                let apiResult = await apiController.cancel(
                                    reason: .systemError(details: "Passkey attestation failed: \(passkeyError)")
                                )

                                let passkeyUnderlyingError: (any Error & Sendable)? = {
                                    switch passkeyError {
                                    case .general(_, let error, _), .passkeysNoCredential(_, let error, _): return error
                                    }
                                }()

                                if apiResult.isCanceled {
                                    guard await self.isAlive() else { return }
                                    await self.stream.yield(.complete(.canceled(.systemError(details: "Operation canceled"))))
                                    return
                                }

                                await self.stream.yield(
                                    .complete(
                                        .failure(
                                            PasskeyAttestationOperationFailure.integration(
                                                .providerFailed(
                                                    errorCode: .passkeyNotCreated,
                                                    message: passkeyError.description,
                                                    underlyingError: passkeyUnderlyingError
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
    internal func start(params: PasskeyAttestationOperationParams? = nil) -> PasskeyAttestationOperationController {
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

        let operationParams: PasskeyAttestationOperationParams?
        if let params {
            guard let typedParams = params as? PasskeyAttestationOperationParams else {
                return .unavailable("Unsupported params type: \(String(describing: type(of: params)))")
            }
            operationParams = typedParams
        } else {
            operationParams = nil
        }

        let accessToken = operationParams?.accessToken ?? context?.accessToken
        let loginID: LoginID?
        if let provided = operationParams?.loginID {
            loginID = provided
        } else {
            do {
                loginID = try context?.loginID(loginIDValidator: loginIDValidator)
            } catch let error {
                if accessToken == nil {
                    return .unavailable(error.message)
                }
                loginID = nil
            }
        }

        guard loginID != nil || accessToken != nil else {
            return .unavailable("LoginID or AccessToken required")
        }

        return .available
    }

    private func unexpectedEventError(
        eventDescription: String,
        state: PasskeyAttestationOperationState
    ) -> PasskeyAttestationOperationFailure {
        .unexpected(message: "\(Self.self): Unexpected event [\(eventDescription)] for state [\(state)]")
    }

    private func isAlive() async -> Bool {
        await MainActor.run { if case .completed = self.state { false } else { true } }
    }

    @MainActor
    private func markCompletedIfNeeded(_ result: OperationResult<AttestationResponse, PasskeyAttestationOperationFailure>) -> Bool {
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
            self.taskRefs.clear([.timeout, .ui])
            await MainActor.run { self.operationRegistry.unregister(id: self.operationID) }
            self.controllerImpl._releaseOwner()
            self.controllerImpl.cancel(reason)
            await self.stream.finish()
        }
    }
}

extension PasskeyAttestationOperationImpl {

    internal static func create(resolver: any DIContainerResolver) -> any PasskeyAttestationOperation {
        do {
            let resolverWithContext = (resolver as! any DIContainer).withContext("PasskeyAttestationOperation") { _ in }
            return PasskeyAttestationOperationImpl(
                operationType: .passkeyCreation,
                operationRegistry: try resolver.getOrThrow(type: (any OperationRegistry).self) as! OperationRegistryImpl,
                ui: try resolver.getOrThrow(type: (any PasskeyAttestationUI).self),
                api: try resolverWithContext.getOrThrow(type: (any PasskeyAttestationAPI).self),
                taskScope: try resolver.getOrThrow(type: TaskScope.self),
                context: resolver.getOrNil(type: Context.self),
                loginIDValidator: resolver.getOrNil(type: (any LoginIDValidator).self),
                logger: resolver.getOrNil(type: OwnIDLogRouter.self),
                unsatisfiedDependencies: resolver.getUnsatisfiedDependencies(for: (any PasskeyAttestationOperation).self)
            )
        } catch {
            return Failed(error: error)
        }
    }
}

/// Unavailable operation returned when construction cannot provide a usable runtime.
///
/// Starting this object returns a controller that is already completed with ``PasskeyAttestationOperationFailure``, does
/// not register in ``OperationRegistry``, and reports unavailable with the same diagnostic message.
private final class Failed: PasskeyAttestationOperation, @unchecked Sendable {
    let operationType: OperationType = .passkeyCreation
    let operationID: OperationID = OperationType.passkeyCreation.createOperationID()
    let controller: PasskeyAttestationOperationController
    private let controllerImpl: OperationControllerImpl<AttestationResponse, PasskeyAttestationOperationFailure>
    private let failure: PasskeyAttestationOperationFailure

    init(error: any Error) {
        let controller = OperationControllerImpl<AttestationResponse, PasskeyAttestationOperationFailure>(operationID: operationID) { _ in }
        let failure = PasskeyAttestationOperationFailure.unexpected(
            message: String(describing: error),
            underlyingError: error.asSendableError()
        )
        self.failure = failure
        controller.fail(failure)
        self.controllerImpl = controller
        self.controller = controller
    }

    @discardableResult
    func start(params: PasskeyAttestationOperationParams? = nil) -> PasskeyAttestationOperationController {
        controller
    }

    func availability(params: (any CapabilityParams)?) async -> Availability {
        .unavailable(failure.message)
    }

    @MainActor
    func stateStream() -> AsyncStream<PasskeyAttestationOperationState> {
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

extension LoginIDResolutionError {
    fileprivate func toPasskeyAttestationOperationFailure() -> PasskeyAttestationOperationFailure {
        switch self {
        case .missingLoginIDValidator(let errorCode, let message):
            return .integration(.missingProvider(errorCode: errorCode, message: message, capability: "LoginIDValidator"))
        case .loginIDTypeNotSupported(let errorCode, let message):
            return .input(.unsupportedLoginIDType(errorCode: errorCode, message: message))
        case .loginIDValidation(let errorCode, let message, let loginID, let regex):
            return .input(.invalidLoginID(errorCode: errorCode, message: message, loginID: loginID, regex: regex))
        }
    }
}

extension PasskeyAttestationStartAPIFailure {
    fileprivate func toOperationFailure() -> PasskeyAttestationOperationFailure {
        switch self {
        case .badRequest(.invalidArgument(let errorCode, let message)), .badRequest(.unknown(let errorCode, let message)):
            return .input(.invalidRequest(errorCode: errorCode, message: message, apiFailure: self))
        case .badRequest(.invalidLoginID(let errorCode, let message, let loginID, let regex)):
            return .input(.invalidLoginID(errorCode: errorCode, message: message, loginID: loginID, regex: regex, apiFailure: self))
        case .badRequest(.unsupportedLoginIDType(let errorCode, let message)):
            return .input(.unsupportedLoginIDType(errorCode: errorCode, message: message, apiFailure: self))
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

extension PasskeyAttestationVerifyAPIFailure {
    fileprivate func toOperationFailure() -> PasskeyAttestationOperationFailure {
        switch self {
        case .badRequest(.invalidArgument(let errorCode, let message)), .badRequest(.unknown(let errorCode, let message)):
            return .input(.invalidRequest(errorCode: errorCode, message: message, apiFailure: self))
        case .badRequest(.invalidChallenge(let errorCode, let message, let challengeID)):
            return .challenge(.invalid(errorCode: errorCode, message: message, challengeID: challengeID, apiFailure: self))
        case .badRequest(.maximumAttemptsReached(let errorCode, let message, let challengeID)):
            return .challenge(.maximumAttemptsReached(errorCode: errorCode, message: message, challengeID: challengeID, apiFailure: self))
        case .unauthorized(let errorCode, let message):
            return .access(.unauthorized(errorCode: errorCode, message: message, apiFailure: self))
        case .forbidden(let errorCode, let message):
            return .access(.forbidden(errorCode: errorCode, message: message, apiFailure: self))
        case .userNotFound(let errorCode, let message):
            return .access(.userNotFound(errorCode: errorCode, message: message, apiFailure: self))
        case .unexpected(let errorCode, let message, let underlyingError):
            return .unexpected(errorCode: errorCode, message: message, apiFailure: self, underlyingError: underlyingError)
        }
    }
}
