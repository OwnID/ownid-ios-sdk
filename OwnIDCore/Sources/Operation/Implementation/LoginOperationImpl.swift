import Foundation

internal final class LoginOperationImpl: LoginOperation, @unchecked Sendable {
    internal enum Event: Sendable {
        case start(LoginOperationParams?)
        case abort(Reason)
        case complete(OperationResult<LoginResponse, LoginOperationFailure>)
    }

    internal let operationType: OperationType
    internal let operationID: OperationID
    private let operationRegistry: OperationRegistryImpl
    private let loginIDValidator: any LoginIDValidator
    private let loginAPI: any LoginAPI
    private let discoverAPI: any DiscoverAPI
    private let context: Context?
    private let logger: OwnIDLogRouter?
    private let taskScope: TaskScope
    private let unsatisfiedDependencies: [String]?

    @MainActor @BroadcastedState private var state: LoginOperationState = .created
    @MainActor internal func stateStream() -> AsyncStream<LoginOperationState> { _state.stream() }

    private let stream = OperationEventStream<Event>()

    private lazy var controllerImpl: OperationControllerImpl<LoginResponse, LoginOperationFailure> = {
        let controller = OperationControllerImpl<LoginResponse, LoginOperationFailure>(operationID: operationID) { [weak self] reason in
            guard let self else { return }
            taskScope.spawn { await self.stream.yield(.abort(reason)) }
        }
        controller._attachOwner(self)
        return controller
    }()

    internal var controller: LoginOperationController { controllerImpl }

    internal init(
        operationType: OperationType,
        operationRegistry: OperationRegistryImpl,
        loginIDValidator: any LoginIDValidator,
        loginAPI: any LoginAPI,
        discoverAPI: any DiscoverAPI,
        context: Context?,
        logger: OwnIDLogRouter?,
        taskScope: TaskScope,
        unsatisfiedDependencies: [String]? = nil
    ) {
        self.operationType = operationType
        self.operationID = operationType.createOperationID()
        self.operationRegistry = operationRegistry
        self.loginIDValidator = loginIDValidator
        self.loginAPI = loginAPI
        self.discoverAPI = discoverAPI
        self.context = context
        self.logger = logger
        self.taskScope = taskScope
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

                            let params = params ?? LoginOperationParams()
                            let traceParent = params.traceParent ?? TraceContext.generateTraceParent()
                            let accessToken = params.accessToken ?? self.context?.accessToken

                            if let accessToken {
                                let apiParams = LoginAPIParams(accessToken: accessToken, traceParent: traceParent)
                                let apiResult = await self.loginAPI.start(params: apiParams)
                                if case .failure(let apiError) = apiResult {
                                    self.logger?.logI(
                                        source: self,
                                        prefix: "Event.Start",
                                        message: "Login API failed: \(apiError.message)"
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
                                return
                            }

                            let loginID: LoginID?
                            if let provided = params.loginID {
                                loginID = provided
                            } else {
                                do {
                                    loginID = try self.context?.loginID(loginIDValidator: self.loginIDValidator)
                                } catch let error {
                                    let contextError = error as! LoginIDResolutionError
                                    let failure = contextError.toOperationFailure()
                                    guard await self.isAlive() else { return }
                                    await self.stream.yield(.complete(.failure(failure)))
                                    return
                                }
                            }

                            guard let loginID else {
                                guard await self.isAlive() else { return }
                                await self.stream.yield(
                                    .complete(
                                        .failure(
                                            .input(
                                                .missingLoginIDOrAccessToken(
                                                    errorCode: .invalidArgument,
                                                    message: "AccessToken or LoginId required"
                                                )
                                            )
                                        )
                                    )
                                )
                                return
                            }

                            do {
                                _ = try self.loginIDValidator.validate(loginID)
                            } catch let error {
                                let validationError = error as! LoginIDValidationError
                                let failure = validationError.toOperationFailure()
                                guard await self.isAlive() else { return }
                                await self.stream.yield(.complete(.failure(failure)))
                                return
                            }

                            let discoverParams = DiscoverAPIParams(loginID: loginID, traceParent: traceParent)
                            let apiResult = await self.discoverAPI.start(params: discoverParams)
                            if case .failure(let apiError) = apiResult {
                                self.logger?.logI(
                                    source: self,
                                    prefix: "Event.Start",
                                    message: "Discover API failed: \(apiError.message)"
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
    internal func start(params: LoginOperationParams? = nil) -> LoginOperationController {
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

        let operationParams: LoginOperationParams?
        if let params {
            guard let typedParams = params as? LoginOperationParams else {
                return .unavailable("Unsupported params type: \(String(describing: type(of: params)))")
            }
            operationParams = typedParams
        } else {
            operationParams = nil
        }

        let accessToken = operationParams?.accessToken ?? context?.accessToken
        if accessToken != nil { return .available }

        let loginID: LoginID?
        if let provided = operationParams?.loginID {
            loginID = provided
        } else {
            do {
                loginID = try context?.loginID(loginIDValidator: loginIDValidator)
            } catch let error {
                return .unavailable(error.message)
            }
        }

        guard let loginID else {
            return .unavailable("AccessToken or LoginId required")
        }

        do {
            _ = try loginIDValidator.validate(loginID)
            return .available
        } catch let error {
            return .unavailable(error.message)
        }
    }

    private func isAlive() async -> Bool {
        await MainActor.run { if case .completed = self.state { false } else { true } }
    }

    @MainActor
    private func markCompletedIfNeeded(_ result: OperationResult<LoginResponse, LoginOperationFailure>) -> Bool {
        if case .completed = self.state { return false }
        self.state = .completed(result)
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

extension LoginOperationImpl {

    internal static func create(resolver: any DIContainerResolver) -> any LoginOperation {
        do {
            let resolverWithContext = (resolver as! any DIContainer).withContext("LoginOperation") { _ in }
            return LoginOperationImpl(
                operationType: .sessionCreation,
                operationRegistry: try resolver.getOrThrow(type: (any OperationRegistry).self) as! OperationRegistryImpl,
                loginIDValidator: try resolver.getOrThrow(type: (any LoginIDValidator).self),
                loginAPI: try resolverWithContext.getOrThrow(type: (any LoginAPI).self),
                discoverAPI: try resolverWithContext.getOrThrow(type: (any DiscoverAPI).self),
                context: resolver.getOrNil(type: Context.self),
                logger: resolver.getOrNil(type: OwnIDLogRouter.self),
                taskScope: try resolver.getOrThrow(type: TaskScope.self),
                unsatisfiedDependencies: resolver.getUnsatisfiedDependencies(for: (any LoginOperation).self)
            )

        } catch {
            return Failed(error: error)
        }
    }
}

private final class Failed: LoginOperation, @unchecked Sendable {
    let operationType: OperationType = .sessionCreation
    let operationID: OperationID = OperationType.sessionCreation.createOperationID()
    let controller: LoginOperationController
    private let controllerImpl: OperationControllerImpl<LoginResponse, LoginOperationFailure>
    private let failure: LoginOperationFailure

    init(error: any Error) {
        let controller = OperationControllerImpl<LoginResponse, LoginOperationFailure>(operationID: operationID) { _ in }
        let failure = LoginOperationFailure.unexpected(message: String(describing: error), underlyingError: error.asSendableError())
        self.failure = failure
        controller.fail(failure)
        self.controllerImpl = controller
        self.controller = controller
    }

    @discardableResult
    func start(params: LoginOperationParams? = nil) -> LoginOperationController {
        controller
    }

    func availability(params: (any CapabilityParams)?) async -> Availability {
        .unavailable(failure.message)
    }

    @MainActor
    func stateStream() -> AsyncStream<LoginOperationState> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                let result = await controller.whenSettled()
                continuation.yield(.completed(result))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

extension LoginIDResolutionError {
    fileprivate func toOperationFailure() -> LoginOperationFailure {
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

extension LoginIDValidationError {
    fileprivate func toOperationFailure() -> LoginOperationFailure {
        switch self {
        case .typeNotSupported(let errorCode, let message):
            return .input(.unsupportedLoginIDType(errorCode: errorCode, message: message))
        case .validationFailed(let errorCode, let message, let loginID, let regex):
            return .input(.invalidLoginID(errorCode: errorCode, message: message, loginID: loginID, regex: regex))
        }
    }
}

extension LoginAPIFailure {
    fileprivate func toOperationFailure() -> LoginOperationFailure {
        switch self {
        case .badRequest(.invalidArgument(let errorCode, let message)),
            .badRequest(.unknown(let errorCode, let message)):
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
        case .unexpected(let errorCode, let message, let underlyingError):
            return .unexpected(errorCode: errorCode, message: message, apiFailure: self, underlyingError: underlyingError)
        }
    }
}

extension DiscoverAPIFailure {
    fileprivate func toOperationFailure() -> LoginOperationFailure {
        switch self {
        case .badRequest(.invalidArgument(let errorCode, let message)),
            .badRequest(.unknown(let errorCode, let message)):
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
        case .unexpected(let errorCode, let message, let underlyingError):
            return .unexpected(errorCode: errorCode, message: message, apiFailure: self, underlyingError: underlyingError)
        }
    }
}
