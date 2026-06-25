import Foundation

/// Instance-scoped runtime for one ``LoginIDCollectOperation`` lifecycle.
///
/// The namespace entry creates a fresh runtime for each launch. This runtime registers its controller while the operation
/// can be presented by SDK UI hosts, owns all state and effect callbacks for that run, and unregisters after the
/// controller settles or cleanup completes. Abort requests are operation-owned cancellation inputs; callers must observe
/// settlement through the controller.
internal final class LoginIDCollectOperationImpl: LoginIDCollectOperation, @unchecked Sendable {

    enum Event: Sendable {
        enum UIEvent: Sendable {
            case loginIDChanged(String)
            case `continue`
            case cancel
        }

        case start(LoginIDCollectOperationParams?)
        case ui(UIEvent)
        case errorStringsUpdated(ErrorStrings)
        case abort(Reason)
        case complete(OperationResult<LoginID, LoginIDCollectOperationFailure>)
    }

    internal let operationType: OperationType
    internal let operationID: OperationID
    private let operationRegistry: OperationRegistryImpl
    private let loginIDConfig: any LoginIDConfigurationProvider
    private let loginIDValidator: any LoginIDValidator
    private let ui: any LoginIDCollectUI
    private let taskScope: TaskScope
    private let errorStringsProvider: (any ErrorStringsProvider)?
    private let context: Context?
    private let logger: OwnIDLogRouter?
    private let unsatisfiedDependencies: [String]?
    private enum TaskRefKey { case timeout, errorStrings }
    private let taskRefs = OperationTaskRefs<TaskRefKey>()
    private var errorStrings: ErrorStrings = .default

    private let stream = OperationEventStream<Event>()
    private static let collectableLoginIDTypes: Set<LoginIDType> = [.email, .phoneNumber, .userName]

    private lazy var controller: LoginIDCollectOperationControllerImpl = {
        let controller = LoginIDCollectOperationControllerImpl(operationID: operationID) { [weak self] reason in
            guard let self else { return }
            taskScope.spawn { await self.stream.yield(.abort(reason)) }
        }
        controller._attachOwner(self)
        return controller
    }()

    internal init(
        operationType: OperationType,
        operationRegistry: OperationRegistryImpl,
        loginIDConfig: any LoginIDConfigurationProvider,
        loginIDValidator: any LoginIDValidator,
        ui: any LoginIDCollectUI,
        taskScope: TaskScope,
        errorStringsProvider: (any ErrorStringsProvider)?,
        context: Context?,
        logger: OwnIDLogRouter?,
        unsatisfiedDependencies: [String]? = nil
    ) {
        self.operationType = operationType
        self.operationID = operationType.createOperationID()
        self.operationRegistry = operationRegistry
        self.loginIDConfig = loginIDConfig
        self.loginIDValidator = loginIDValidator
        self.ui = ui
        self.taskScope = taskScope
        self.errorStringsProvider = errorStringsProvider
        self.context = context
        self.logger = logger
        self.unsatisfiedDependencies = unsatisfiedDependencies

        taskScope.onShutdown { [weak self] in
            self?.handleShutdown()
        }

        if let provider = errorStringsProvider {
            self.taskRefs.replace(
                .errorStrings,
                with: taskScope.spawn { [weak self] in
                    guard let self else { return }
                    for await maybeStrings in provider.getStrings(params: ErrorStringsParams()) {
                        if Task.isCancelled { break }
                        let strings = maybeStrings ?? .default
                        await self.stream.yield(.errorStringsUpdated(strings))
                    }
                }
            )
        }

        taskScope.spawn(
            onCancel: { [stream = self.stream] in Task { await stream.finish() } }
        ) { [weak self, stream = self.stream] in
            for await event in stream.sequence {
                if Task.isCancelled { break }
                guard let self else { break }

                switch event {
                case .start(let params):
                    let state = await MainActor.run { self.controller.state }
                    guard case .created = state else { break }
                    await MainActor.run { self.operationRegistry.register(controller: self.controller) }

                    let params = params ?? LoginIDCollectOperationParams()

                    let collectableTypes = self.loginIDConfig.configuration.supportedTypes.filter {
                        Self.collectableLoginIDTypes.contains($0)
                    }
                    guard !collectableTypes.isEmpty else {
                        await self.completeOperation(
                            .failure(
                                .integration(
                                    .noSupportedLoginIDTypes(errorCode: .loginIDTypeNotSupported, message: "No supported LoginID.Types")
                                )
                            )
                        )
                        continue
                    }

                    let loginIDValue: String
                    if let provided = params.loginID ?? self.context?.loginID {
                        guard collectableTypes.contains(provided.type) else {
                            await self.completeOperation(
                                .failure(
                                    .input(
                                        .unsupportedLoginIDType(
                                            errorCode: .loginIDTypeNotSupported,
                                            message: "Unsupported LoginID.Type: \(provided.type)"
                                        )
                                    )
                                )
                            )
                            continue
                        }

                        if let loginID = try? self.loginIDValidator.validate(provided) {
                            await self.completeOperation(.success(loginID))
                            continue
                        }

                        loginIDValue = provided.id
                    } else if let rawLoginID = self.context?.rawLoginID {
                        if let loginID = try? self.loginIDValidator.appendWithType(rawLoginID) {
                            guard collectableTypes.contains(loginID.type) else {
                                await self.completeOperation(
                                    .failure(
                                        .input(
                                            .unsupportedLoginIDType(
                                                errorCode: .loginIDTypeNotSupported,
                                                message: "Unsupported LoginID.Type: \(loginID.type)"
                                            )
                                        )
                                    )
                                )
                                continue
                            }

                            if let validated = try? self.loginIDValidator.validate(loginID) {
                                await self.completeOperation(.success(validated))
                                continue
                            }
                        }
                        loginIDValue = rawLoginID
                    } else {
                        loginIDValue = ""
                    }

                    self.taskRefs.replace(
                        .timeout,
                        with: taskScope.spawn { [weak self] in
                            guard let self else { return }
                            do {
                                try await Task.sleep(nanoseconds: Self.operationTimeoutNanoseconds)
                                await self.stream.yield(.abort(.timeout))
                            } catch {}
                        }
                    )

                    let uiState = LoginIDCollectUIState(
                        loginIDValue: loginIDValue,
                        collectableLoginIDTypes: collectableTypes,
                        error: nil,
                        onLoginIDChange: { [weak self] newLoginIDValue in
                            guard let self else { return }
                            taskScope.spawn { await self.stream.yield(.ui(.loginIDChanged(newLoginIDValue))) }
                        },
                        onContinue: { [weak self, onUIClick = params.onUIClick] in
                            guard let self else { return }
                            onUIClick?(self.operationID)
                            taskScope.spawn { await self.stream.yield(.ui(.continue)) }
                        },
                        onCancel: { [weak self, onUIClick = params.onUIClick] in
                            guard let self else { return }
                            onUIClick?(self.operationID)
                            taskScope.spawn { await self.stream.yield(.ui(.cancel)) }
                        }
                    )

                    let didActivate = await MainActor.run { () -> Bool in
                        if case .completed = self.controller.state { return false }
                        self.controller.state = .active(uiState: uiState)
                        return true
                    }
                    guard didActivate else {
                        self.taskRefs.clear(.timeout)
                        continue
                    }

                    let startError = await MainActor.run {
                        self.ui.start(controller: self.controller)
                    }
                    if let startError {
                        self.taskRefs.clear(.timeout)
                        await self.stream.yield(.complete(.failure(.integration(startError))))
                    }

                case .ui(let uiEvent):
                    let state = await MainActor.run { self.controller.state }
                    switch state {
                    case .created:
                        let error = self.unexpectedEventError(eventDescription: "\(uiEvent)", state: state)
                        self.taskRefs.clear(.timeout)
                        await self.stream.yield(.complete(.failure(error)))

                    case .active(let uiState):
                        switch uiEvent {
                        case .loginIDChanged(let newLoginIDValue):
                            let newState = LoginIDCollectUIState(
                                loginIDValue: newLoginIDValue,
                                collectableLoginIDTypes: uiState.collectableLoginIDTypes,
                                error: nil,
                                onLoginIDChange: uiState.onLoginIDChange,
                                onContinue: uiState.onContinue,
                                onCancel: uiState.onCancel
                            )
                            await MainActor.run { self.controller.state = .active(uiState: newState) }

                        case .continue:
                            var acceptedLoginID: LoginID?
                            var lastValidationErrorCode: ErrorCode?

                            for type in uiState.collectableLoginIDTypes {
                                do {
                                    acceptedLoginID = try self.loginIDValidator.validate(LoginID(id: uiState.loginIDValue, type: type))
                                } catch let error {
                                    let validationError = error as! LoginIDValidationError
                                    lastValidationErrorCode = validationError.errorCode
                                }
                                if acceptedLoginID != nil { break }
                            }

                            if let acceptedLoginID {
                                self.taskRefs.clear(.timeout)
                                await self.stream.yield(.complete(.success(acceptedLoginID)))
                            } else {
                                let errorCode = lastValidationErrorCode ?? .loginIDValidationFailed
                                let newState = LoginIDCollectUIState(
                                    loginIDValue: uiState.loginIDValue,
                                    collectableLoginIDTypes: uiState.collectableLoginIDTypes,
                                    error: errorCode.toUIError(errorStrings: self.errorStrings),
                                    onLoginIDChange: uiState.onLoginIDChange,
                                    onContinue: uiState.onContinue,
                                    onCancel: uiState.onCancel
                                )
                                await MainActor.run { self.controller.state = .active(uiState: newState) }
                            }

                        case .cancel:
                            self.taskRefs.clear(.timeout)
                            await self.stream.yield(.complete(.canceled(.userClose())))
                        }

                    case .completed:
                        break
                    }

                case .errorStringsUpdated(let newStrings):
                    self.errorStrings = newStrings
                    let state = await MainActor.run { self.controller.state }
                    if case .active(let uiState) = state, let currentError = uiState.error {
                        let newState = LoginIDCollectUIState(
                            loginIDValue: uiState.loginIDValue,
                            collectableLoginIDTypes: uiState.collectableLoginIDTypes,
                            error: currentError.errorCode.toUIError(errorStrings: newStrings),
                            onLoginIDChange: uiState.onLoginIDChange,
                            onContinue: uiState.onContinue,
                            onCancel: uiState.onCancel
                        )
                        await MainActor.run { self.controller.state = .active(uiState: newState) }
                    }

                case .abort(let reason):
                    let state = await MainActor.run { self.controller.state }
                    switch state {
                    case .created:
                        self.taskRefs.clear(.timeout)
                        await self.stream.yield(.complete(.canceled(reason)))
                    case .active:
                        self.taskRefs.clear(.timeout)
                        await self.stream.yield(.complete(.canceled(reason)))
                    case .completed: break
                    }

                case .complete(let result):
                    await self.completeOperation(result)
                }
            }
        }
    }

    deinit {
        taskScope.shutdown()
        self.logger?.logV(source: self, prefix: #function, message: "Invoked")
    }

    @discardableResult
    internal func start(params: LoginIDCollectOperationParams? = nil) -> any OperationController<LoginID, LoginIDCollectOperationFailure> {
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

        let operationParams: LoginIDCollectOperationParams?
        if let params {
            guard let typedParams = params as? LoginIDCollectOperationParams else {
                return .unavailable("Unsupported params type: \(String(describing: type(of: params)))")
            }
            operationParams = typedParams
        } else {
            operationParams = nil
        }

        let collectableTypes = loginIDConfig.configuration.supportedTypes.filter { Self.collectableLoginIDTypes.contains($0) }
        guard !collectableTypes.isEmpty else {
            return .unavailable("No supported LoginID.Types")
        }

        if let loginID = operationParams?.loginID ?? context?.loginID {
            return collectableTypes.contains(loginID.type)
                ? .available
                : .unavailable("Unsupported LoginID.Type: \(loginID.type)")
        }

        guard let rawLoginID = context?.rawLoginID else { return .available }

        do {
            let loginID = try loginIDValidator.appendWithType(rawLoginID)
            return collectableTypes.contains(loginID.type) ? .available : .unavailable("Unsupported LoginID.Type: \(loginID.type)")
        } catch {
            return .available
        }
    }

    private func unexpectedEventError(eventDescription: String, state: LoginIDCollectOperationState) -> LoginIDCollectOperationFailure {
        .unexpected(message: "\(Self.self): Unexpected event [\(eventDescription)] for state [\(state)]")
    }

    private func completeOperation(_ result: OperationResult<LoginID, LoginIDCollectOperationFailure>) async {
        self.taskRefs.clear([.timeout, .errorStrings])
        let didSettle = await self.markCompletedIfNeeded(result)
        guard didSettle else { return }
        await MainActor.run { self.operationRegistry.unregister(id: self.operationID) }
        self.controller._releaseOwner()
        result
            .onSuccess { payload in self.controller.complete(payload) }
            .onCanceled { reason in
                self.logger?.logD(source: self, prefix: "Canceled with reason", message: reason.description)
                self.controller.cancel(reason)
            }
            .onError { error in
                self.logger?.logD(source: self, prefix: "Completed with error", message: error.message)
                self.controller.fail(error)
            }
        await self.stream.finish()
    }

    @MainActor
    private func markCompletedIfNeeded(_ result: OperationResult<LoginID, LoginIDCollectOperationFailure>) -> Bool {
        if case .completed = self.controller.state { return false }
        self.controller.state = .completed(result: result)
        return true
    }

    private func handleShutdown() {
        Task { [weak self] in
            guard let self else { return }
            let reason = Reason.systemError(details: "Operation canceled")
            await self.completeOperation(.canceled(reason))
        }
    }

    private static let operationTimeoutNanoseconds: UInt64 = 300 * 1_000_000_000
}

extension LoginIDCollectOperationImpl {

    internal static func create(resolver: any DIContainerResolver) -> any LoginIDCollectOperation {
        do {
            return LoginIDCollectOperationImpl(
                operationType: .loginIDCollect,
                operationRegistry: try resolver.getOrThrow(type: (any OperationRegistry).self) as! OperationRegistryImpl,
                loginIDConfig: try resolver.getOrThrow(type: (any LoginIDConfigurationProvider).self),
                loginIDValidator: try resolver.getOrThrow(type: (any LoginIDValidator).self),
                ui: try resolver.getOrThrow(type: (any LoginIDCollectUI).self),
                taskScope: try resolver.getOrThrow(type: TaskScope.self),
                errorStringsProvider: resolver.getOrNil(type: (any ErrorStringsProvider).self),
                context: resolver.getOrNil(type: Context.self),
                logger: resolver.getOrNil(type: OwnIDLogRouter.self),
                unsatisfiedDependencies: resolver.getUnsatisfiedDependencies(for: (any LoginIDCollectOperation).self)
            )
        } catch {
            return Failed(error: error)
        }
    }
}

/// Unavailable operation returned when construction cannot provide a usable runtime.
///
/// Starting this object returns a controller that is already completed with
/// ``LoginIDCollectOperationFailure/unexpected(errorCode:message:underlyingError:)``, does not register in
/// ``OperationRegistry``, and reports unavailable with the same diagnostic message.
private final class Failed: LoginIDCollectOperation, @unchecked Sendable {
    let operationType: OperationType = .loginIDCollect
    let operationID: OperationID = OperationType.loginIDCollect.createOperationID()
    private let controllerImpl: LoginIDCollectOperationControllerImpl
    private let failure: LoginIDCollectOperationFailure

    init(error: any Error) {
        let failure = LoginIDCollectOperationFailure.unexpected(
            message: String(describing: error),
            underlyingError: error.asSendableError()
        )
        let controller = LoginIDCollectOperationControllerImpl(
            operationID: operationID,
            onUserAborted: { _ in },
            initialState: .completed(result: .failure(failure))
        )
        self.failure = failure
        controller.fail(failure)
        self.controllerImpl = controller
    }

    @discardableResult
    func start(params: LoginIDCollectOperationParams? = nil) -> any OperationController<LoginID, LoginIDCollectOperationFailure> {
        controllerImpl
    }

    func availability(params: (any CapabilityParams)?) async -> Availability {
        .unavailable(failure.message)
    }
}

/// Concrete controller for login ID collection.
///
/// In addition to the standard operation settlement contract, this controller exposes the public state stream used by
/// host-managed login ID collection UI. The operation runtime remains the only owner allowed to replace state or settle
/// the controller.
internal final class LoginIDCollectOperationControllerImpl:
    OperationControllerImpl<LoginID, LoginIDCollectOperationFailure>, LoginIDCollectOperationController, @unchecked Sendable
{
    @MainActor @BroadcastedState private var currentState: LoginIDCollectOperationState = .created

    internal init(
        operationID: OperationID,
        onUserAborted: @escaping @Sendable (Reason) -> Void,
        initialState: LoginIDCollectOperationState = .created
    ) {
        self._currentState = BroadcastedState(wrappedValue: initialState)
        super.init(operationID: operationID, onUserAborted: onUserAborted)
    }

    @MainActor internal var state: LoginIDCollectOperationState {
        get { currentState }
        set { currentState = newValue }
    }

    @MainActor
    func stateStream() -> AsyncStream<LoginIDCollectOperationState> {
        _currentState.stream()
    }
}
