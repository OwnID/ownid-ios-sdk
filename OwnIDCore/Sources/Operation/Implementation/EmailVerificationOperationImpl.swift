import Foundation

internal final class EmailVerificationOperationImpl: EmailVerificationOperation, @unchecked Sendable {

    enum Event: Sendable {
        enum UIEvent: Sendable { case codeEntered(String), resend, cancel, notYou }
        enum APIEvent: Sendable {
            case start(APIResult<any EmailVerificationAPIController, EmailVerificationStartAPIFailure>),
                complete(APIResult<AccessOrProofToken, EmailVerificationCompleteAPIFailure>),
                resend(APIResult<Void, EmailVerificationResendAPIFailure>),
                cancel(Reason)
        }
        case start(EmailVerificationOperationParams?)
        case api(APIEvent)
        case ui(UIEvent)
        case errorStringsUpdated(ErrorStrings)
        case abort(Reason)
        case complete(OperationResult<AccessOrProofToken, EmailVerificationOperationFailure>)
    }

    internal let operationType: OperationType
    internal let operationID: OperationID
    private let operationRegistry: OperationRegistryImpl
    private let ui: any EmailVerificationUI
    private let api: any EmailVerificationAPI
    private let errorStringsProvider: (any ErrorStringsProvider)?
    private let context: Context?
    private let loginIDValidator: (any LoginIDValidator)?
    private let taskScope: TaskScope
    private let logger: OwnIDLogRouter?
    private let unsatisfiedDependencies: [String]?
    private enum TaskRefKey { case timeout, errorStrings }
    private let taskRefs = OperationTaskRefs<TaskRefKey>()
    private var errorStrings: ErrorStrings = .default

    private let stream = OperationEventStream<Event>()

    private lazy var controller: EmailVerificationOperationControllerImpl = {
        let controller = EmailVerificationOperationControllerImpl(operationID: operationID) { [weak self] reason in
            guard let self else { return }
            taskScope.spawn { await self.stream.yield(.abort(reason)) }
        }
        controller._attachOwner(self)
        return controller
    }()

    internal init(
        operationType: OperationType,
        operationRegistry: OperationRegistryImpl,
        ui: any EmailVerificationUI,
        api: any EmailVerificationAPI,
        taskScope: TaskScope,
        errorStringsProvider: (any ErrorStringsProvider)?,
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
        self.errorStringsProvider = errorStringsProvider
        self.context = context
        self.loginIDValidator = loginIDValidator
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
                    if case .created = state {
                        await MainActor.run { self.operationRegistry.register(controller: self.controller) }
                        let resolvedParams = params ?? EmailVerificationOperationParams()
                        let accessToken = resolvedParams.accessToken ?? self.context?.accessToken
                        var loginID: LoginID?
                        if let provided = resolvedParams.loginID {
                            loginID = provided
                        } else {
                            do {
                                loginID = try self.context?.loginID(loginIDValidator: self.loginIDValidator)
                            } catch let error {
                                if accessToken == nil {
                                    let contextError = error as! LoginIDResolutionError
                                    let failure = contextError.toEmailVerificationOperationFailure()
                                    guard await self.isAlive() else { return }
                                    await self.stream.yield(.complete(.failure(failure)))
                                    continue
                                }
                            }
                        }

                        if loginID == nil && accessToken == nil {
                            await self.stream.yield(
                                .complete(
                                    .failure(
                                        .input(
                                            .missingLoginIDOrAccessToken(
                                                errorCode: .invalidArgument,
                                                message: "LoginId or AccessToken required"
                                            )
                                        )
                                    )
                                )
                            )
                            continue
                        }

                        if !loginID.isSupportedVerificationTarget(.email, loginIDHintID: resolvedParams.loginIDHintID) {
                            await self.stream.yield(
                                .complete(
                                    .failure(
                                        .input(
                                            .unsupportedLoginIDType(
                                                errorCode: .loginIDTypeNotSupported,
                                                message: "LoginIDType.Email or LoginIDType.UserName with loginIDHintID required"
                                            )
                                        )
                                    )
                                )
                            )
                            continue
                        }

                        let paramsWithLoginID = EmailVerificationOperationParams(
                            loginID: loginID,
                            loginIDHintID: resolvedParams.loginIDHintID,
                            accessToken: accessToken,
                            onUIClick: resolvedParams.onUIClick,
                            traceParent: resolvedParams.traceParent
                        )

                        let loginIDValue = loginID
                        taskScope.spawn { [weak self, loginIDValue] in
                            guard let self else { return }
                            let apiResult = await self.api.start(
                                params: EmailVerificationAPIParams(
                                    loginID: loginIDValue,
                                    loginIDHintID: paramsWithLoginID.loginIDHintID,
                                    accessToken: accessToken,
                                    verificationMethods: [.otp],
                                    magicLinkRedirectURL: nil,
                                    traceParent: paramsWithLoginID.traceParent ?? TraceContext.generateTraceParent()
                                )
                            )
                            guard await self.isAlive() else { return }
                            await self.stream.yield(.api(.start(apiResult)))
                        }
                        await MainActor.run { self.controller.state = .preparing(params: paramsWithLoginID) }

                        let ui = self.ui
                        let controller = self.controller
                        taskScope.spawn { [weak self] in
                            guard let self else { return }
                            guard await self.isAlive() else { return }
                            let startError = await MainActor.run { ui.start(controller: controller) }
                            if let startError {
                                await self.stream.yield(.complete(.failure(.integration(startError))))
                            }
                        }
                    }

                case .api(let apiEvent):
                    switch apiEvent {
                    case .start(let apiResponse):
                        let state = await MainActor.run { self.controller.state }
                        switch state {
                        case .created:
                            let error = self.unexpectedEventError(eventDescription: "\(apiEvent)", state: state)
                            await self.stream.yield(.complete(.failure(error)))
                        case .preparing(let params):
                            switch apiResponse {
                            case .success(let apiController):
                                self.taskRefs.clear(.timeout)

                                if apiController.challenge.methods.otp == nil {
                                    await self.stream.yield(
                                        .complete(
                                            .failure(
                                                .unexpected(
                                                    errorCode: .integrationError,
                                                    message:
                                                        "OTP challenge method missing; availableChallengeMethods=\(apiController.challenge.methods)"
                                                )
                                            )
                                        )
                                    )
                                } else {
                                    self.taskRefs.replace(
                                        .timeout,
                                        with: taskScope.spawn { [weak self] in
                                            guard let self else { return }
                                            do {
                                                try await Task.sleep(
                                                    nanoseconds: UInt64(apiController.challenge.timeout.milliseconds) * 1_000_000
                                                )
                                                await self.stream.yield(.abort(.timeout))
                                            } catch {}
                                        }
                                    )

                                    let uiState = EmailVerificationUIState(
                                        challenge: apiController.challenge,
                                        onCodeEntered: { [weak self, onUIClick = params.onUIClick] code in
                                            guard let self else { return }
                                            onUIClick?(self.operationID)
                                            taskScope.spawn { await self.stream.yield(.ui(.codeEntered(code))) }
                                        },
                                        onCancel: { [weak self, onUIClick = params.onUIClick] in
                                            guard let self else { return }
                                            onUIClick?(self.operationID)
                                            taskScope.spawn { await self.stream.yield(.ui(.cancel)) }
                                        },
                                        onNotYou: { [weak self, onUIClick = params.onUIClick] in
                                            guard let self else { return }
                                            onUIClick?(self.operationID)
                                            taskScope.spawn { await self.stream.yield(.ui(.notYou)) }
                                        },
                                        onResend: { [weak self, onUIClick = params.onUIClick] in
                                            guard let self else { return }
                                            onUIClick?(self.operationID)
                                            taskScope.spawn { await self.stream.yield(.ui(.resend)) }
                                        }
                                    )
                                    await MainActor.run { self.controller.state = .active(uiState: uiState, apiController: apiController) }
                                }
                            case .failure(let apiError):
                                self.logger?.logI(
                                    source: self,
                                    prefix: "Event.Start",
                                    message: "API start failed: \(apiError.message)"
                                )
                                await self.stream.yield(.complete(.failure(apiError.toOperationFailure())))
                            case .canceled:
                                await self.stream.yield(.complete(.canceled(.systemError(details: "Operation canceled"))))
                            }

                        case .active:
                            let error = self.unexpectedEventError(eventDescription: "\(apiEvent)", state: state)
                            await self.stream.yield(.complete(.failure(error)))
                        case .completed:
                            break
                        }

                    case .complete(let apiResponse):
                        let state = await MainActor.run { self.controller.state }
                        switch state {
                        case .created, .preparing:
                            let error = self.unexpectedEventError(eventDescription: "\(apiEvent)", state: state)
                            await self.stream.yield(.complete(.failure(error)))
                        case .active(let uiState, let apiController):
                            switch apiResponse {
                            case .success(let tokens):
                                await self.stream.yield(.complete(.success(tokens)))
                            case .failure(let apiError):
                                let maximumAttemptsReached: Bool = {
                                    if case .badRequest(.maximumAttemptsReached(_, _, _)) = apiError {
                                        return true
                                    }
                                    return false
                                }()
                                if case .badRequest(.wrongCode(_, _, _)) = apiError {
                                    let newState = EmailVerificationUIState(
                                        challenge: uiState.challenge,
                                        isBusy: false,
                                        error: apiError.errorCode.toUIError(errorStrings: self.errorStrings),
                                        onCodeEntered: uiState.onCodeEntered,
                                        onCancel: uiState.onCancel,
                                        onNotYou: uiState.onNotYou,
                                        onResend: uiState.onResend
                                    )
                                    await MainActor.run { self.controller.state = .active(uiState: newState, apiController: apiController) }
                                } else {
                                    self.taskRefs.clear(.timeout)
                                    let uiErrorCode: ErrorCode = maximumAttemptsReached ? .maximumAttemptsReached : .unknown
                                    let newState = EmailVerificationUIState(
                                        challenge: uiState.challenge,
                                        isBusy: false,
                                        error: uiErrorCode.toUIError(errorStrings: self.errorStrings),
                                        onCodeEntered: { _ in },
                                        onCancel: {},
                                        onNotYou: {},
                                        onResend: {}
                                    )
                                    await MainActor.run { self.controller.state = .active(uiState: newState, apiController: apiController) }
                                    taskScope.spawn { [weak self] in
                                        guard let self else { return }
                                        guard (try? await Task.sleep(nanoseconds: 1_000_000_000)) != nil else { return }
                                        guard await self.isAlive() else { return }
                                        if maximumAttemptsReached {
                                            let reason = Reason.userClose(details: "Maximum attempts reached")
                                            taskScope.spawn {
                                                _ = await apiController.cancel(reason: reason)
                                            }
                                        }
                                        await self.stream.yield(.complete(.failure(apiError.toOperationFailure())))
                                    }
                                }
                            case .canceled:
                                await self.stream.yield(.complete(.canceled(.systemError(details: "Operation canceled"))))
                            }
                        case .completed:
                            break
                        }

                    case .resend(let apiResponse):
                        let state = await MainActor.run { self.controller.state }
                        switch state {
                        case .created, .preparing:
                            let error = self.unexpectedEventError(eventDescription: "\(apiEvent)", state: state)
                            await self.stream.yield(.complete(.failure(error)))
                        case .active(let uiState, let apiController):
                            if apiResponse.isCanceled {
                                await self.stream.yield(.complete(.canceled(.systemError(details: "Operation canceled"))))
                                break
                            }
                            guard let apiError = apiResponse.errorOrNil() else {
                                let newState = EmailVerificationUIState(
                                    challenge: uiState.challenge,
                                    isBusy: false,
                                    error: nil,
                                    onCodeEntered: uiState.onCodeEntered,
                                    onCancel: uiState.onCancel,
                                    onNotYou: uiState.onNotYou,
                                    onResend: uiState.onResend
                                )
                                await MainActor.run { self.controller.state = .active(uiState: newState, apiController: apiController) }
                                break
                            }
                            if case .badRequest(.maximumResendAttemptsReached(_, _, _)) = apiError {
                                var challenge = uiState.challenge
                                let rp = VerificationChallenge.ResendPolicy(
                                    allow: false,
                                    attempts: challenge.resendPolicy.attempts,
                                    debounce: challenge.resendPolicy.debounce
                                )
                                challenge = VerificationChallenge(
                                    challengeID: challenge.challengeID,
                                    resendPolicy: rp,
                                    timeout: challenge.timeout,
                                    attempts: challenge.attempts,
                                    methods: challenge.methods,
                                    channel: challenge.channel
                                )
                                let newState = EmailVerificationUIState(
                                    challenge: challenge,
                                    isBusy: false,
                                    error: apiError.errorCode.toUIError(errorStrings: self.errorStrings),
                                    onCodeEntered: uiState.onCodeEntered,
                                    onCancel: uiState.onCancel,
                                    onNotYou: uiState.onNotYou,
                                    onResend: uiState.onResend
                                )
                                await MainActor.run { self.controller.state = .active(uiState: newState, apiController: apiController) }
                            } else {
                                self.taskRefs.clear(.timeout)
                                let newState = EmailVerificationUIState(
                                    challenge: uiState.challenge,
                                    isBusy: false,
                                    error: ErrorCode.unknown.toUIError(errorStrings: self.errorStrings),
                                    onCodeEntered: { _ in },
                                    onCancel: {},
                                    onNotYou: {},
                                    onResend: {}
                                )
                                await MainActor.run { self.controller.state = .active(uiState: newState, apiController: apiController) }
                                taskScope.spawn { [weak self] in
                                    guard let self else { return }
                                    guard (try? await Task.sleep(nanoseconds: 1_000_000_000)) != nil else { return }
                                    guard await self.isAlive() else { return }
                                    await self.stream.yield(.complete(.failure(apiError.toOperationFailure())))
                                }
                            }

                        case .completed:
                            break
                        }

                    case .cancel(let reason):
                        let state = await MainActor.run { self.controller.state }
                        switch state {
                        case .created, .preparing:
                            let error = self.unexpectedEventError(eventDescription: "\(apiEvent)", state: state)
                            await self.stream.yield(.complete(.failure(error)))
                        case .active:
                            await self.stream.yield(.complete(.canceled(reason)))
                        case .completed:
                            break
                        }
                    }

                case .ui(let uiEvent):
                    let state = await MainActor.run { self.controller.state }
                    switch state {
                    case .created, .preparing:
                        let error = self.unexpectedEventError(eventDescription: "\(uiEvent)", state: state)
                        await self.stream.yield(.complete(.failure(error)))
                    case .active(let uiState, let apiController):
                        if uiState.isBusy {
                            if case .cancel = uiEvent {
                                // Allow cancellation while busy.
                            } else {
                                break
                            }
                        }

                        taskScope.spawn { [weak self] in
                            guard let self else { return }
                            let apiEvent: Event.APIEvent
                            switch uiEvent {
                            case .codeEntered(let code):
                                apiEvent = .complete(await apiController.completeWithCode(code: code))
                            case .resend:
                                apiEvent = .resend(await apiController.resend())
                            case .cancel:
                                let reason = Reason.userClose()
                                _ = await apiController.cancel(reason: reason)
                                apiEvent = .cancel(reason)
                            case .notYou:
                                let reason = Reason.moveToOtherChallenge
                                _ = await apiController.cancel(reason: reason)
                                apiEvent = .cancel(reason)
                            }
                            guard await self.isAlive() else { return }
                            await self.stream.yield(.api(apiEvent))
                        }

                        let busy = EmailVerificationUIState(
                            challenge: uiState.challenge,
                            isBusy: true,
                            error: nil,
                            onCodeEntered: uiState.onCodeEntered,
                            onCancel: uiState.onCancel,
                            onNotYou: uiState.onNotYou,
                            onResend: uiState.onResend
                        )
                        await MainActor.run { self.controller.state = .active(uiState: busy, apiController: apiController) }

                    case .completed:
                        break
                    }

                case .errorStringsUpdated(let newStrings):
                    self.errorStrings = newStrings
                    let state = await MainActor.run { self.controller.state }
                    if case .active(let uiState, let apiController) = state, let currentError = uiState.error {
                        let newState = EmailVerificationUIState(
                            challenge: uiState.challenge,
                            isBusy: uiState.isBusy,
                            error: currentError.errorCode.toUIError(errorStrings: newStrings),
                            onCodeEntered: uiState.onCodeEntered,
                            onCancel: uiState.onCancel,
                            onNotYou: uiState.onNotYou,
                            onResend: uiState.onResend
                        )
                        await MainActor.run { self.controller.state = .active(uiState: newState, apiController: apiController) }
                    }

                case .abort(let reason):
                    let state = await MainActor.run { self.controller.state }
                    switch state {
                    case .created: await self.stream.yield(.complete(.canceled(reason)))
                    case .preparing: await self.stream.yield(.complete(.canceled(reason)))
                    case .active(_, let apiController):
                        self.taskRefs.clear(.timeout)
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
                    self.taskRefs.clear([.errorStrings, .timeout])
                    let didSettle = await self.markCompletedIfNeeded(result)
                    guard didSettle else { break }
                    await MainActor.run { self.operationRegistry.unregister(id: self.operationID) }
                    self.controller._releaseOwner()
                    result
                        .onSuccess { tokens in self.controller.complete(tokens) }
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
            }
        }
    }

    deinit {
        taskScope.shutdown()
        self.logger?.logV(source: self, prefix: #function, message: "Invoked")
    }

    @discardableResult
    internal func start(
        params: EmailVerificationOperationParams? = nil
    ) -> any OperationController<AccessOrProofToken, EmailVerificationOperationFailure> {
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

        let operationParams: EmailVerificationOperationParams?
        if let params {
            guard let typedParams = params as? EmailVerificationOperationParams else {
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

        if loginID == nil && accessToken == nil {
            return .unavailable("LoginId or AccessToken required")
        }

        if !loginID.isSupportedVerificationTarget(.email, loginIDHintID: operationParams?.loginIDHintID) {
            return .unavailable("LoginIDType.Email or LoginIDType.UserName with loginIDHintID required")
        }
        return .available
    }

    private func unexpectedEventError(eventDescription: String, state: EmailVerificationOperationState) -> EmailVerificationOperationFailure
    {
        .unexpected(message: "\(Self.self): Unexpected event [\(eventDescription)] for state [\(state)]")
    }

    private func isAlive() async -> Bool {
        await MainActor.run { if case .completed = self.controller.state { false } else { true } }
    }

    @MainActor
    private func markCompletedIfNeeded(_ result: OperationResult<AccessOrProofToken, EmailVerificationOperationFailure>) -> Bool {
        if case .completed = self.controller.state { return false }
        self.controller.state = .completed(result: result)
        return true
    }

    private func handleShutdown() {
        Task { [weak self] in
            guard let self else { return }
            let reason = Reason.systemError(details: "Operation canceled")
            let didSettle = await self.markCompletedIfNeeded(.canceled(reason))
            guard didSettle else { return }
            self.taskRefs.clear([.errorStrings, .timeout])
            await MainActor.run { self.operationRegistry.unregister(id: self.operationID) }
            self.controller._releaseOwner()
            self.controller.cancel(reason)
            await self.stream.finish()
        }
    }
}

extension EmailVerificationOperationImpl {

    internal static func create(resolver: any DIContainerResolver) -> any EmailVerificationOperation {
        do {
            let resolverWithContext = (resolver as! any DIContainer).withContext("EmailVerificationOperation") { _ in }
            return EmailVerificationOperationImpl(
                operationType: .emailVerification,
                operationRegistry: try resolver.getOrThrow(type: (any OperationRegistry).self) as! OperationRegistryImpl,
                ui: try resolver.getOrThrow(type: (any EmailVerificationUI).self),
                api: try resolverWithContext.getOrThrow(type: (any EmailVerificationAPI).self),
                taskScope: try resolver.getOrThrow(type: TaskScope.self),
                errorStringsProvider: resolver.getOrNil(type: (any ErrorStringsProvider).self),
                context: resolver.getOrNil(type: Context.self),
                loginIDValidator: resolver.getOrNil(type: (any LoginIDValidator).self),
                logger: resolver.getOrNil(type: OwnIDLogRouter.self),
                unsatisfiedDependencies: resolver.getUnsatisfiedDependencies(for: (any EmailVerificationOperation).self)
            )
        } catch {
            return Failed(error: error)
        }
    }
}

private final class Failed: EmailVerificationOperation, @unchecked Sendable {
    let operationType: OperationType = .emailVerification
    let operationID: OperationID = OperationType.emailVerification.createOperationID()
    private let controllerImpl: EmailVerificationOperationControllerImpl
    private let failure: EmailVerificationOperationFailure

    init(error: any Error) {
        let failure = EmailVerificationOperationFailure.unexpected(
            message: String(describing: error),
            underlyingError: error.asSendableError()
        )
        let controller = EmailVerificationOperationControllerImpl(
            operationID: operationID,
            onUserAborted: { _ in },
            initialState: .completed(result: .failure(failure))
        )
        self.failure = failure
        controller.fail(failure)
        self.controllerImpl = controller
    }

    @discardableResult
    func start(
        params: EmailVerificationOperationParams? = nil
    ) -> any OperationController<AccessOrProofToken, EmailVerificationOperationFailure> {
        controllerImpl
    }

    func availability(params: (any CapabilityParams)?) async -> Availability {
        .unavailable(failure.message)
    }
}

internal final class EmailVerificationOperationControllerImpl:
    OperationControllerImpl<AccessOrProofToken, EmailVerificationOperationFailure>, EmailVerificationOperationController,
    @unchecked Sendable
{
    @MainActor @BroadcastedState private var currentState: EmailVerificationOperationState = .created

    internal init(
        operationID: OperationID,
        onUserAborted: @escaping @Sendable (Reason) -> Void,
        initialState: EmailVerificationOperationState = .created
    ) {
        self._currentState = BroadcastedState(wrappedValue: initialState)
        super.init(operationID: operationID, onUserAborted: onUserAborted)
    }

    @MainActor internal var state: EmailVerificationOperationState {
        get { currentState }
        set { currentState = newValue }
    }

    @MainActor
    func stateStream() -> AsyncStream<EmailVerificationOperationState> {
        _currentState.stream()
    }
}

extension LoginIDResolutionError {
    fileprivate func toEmailVerificationOperationFailure() -> EmailVerificationOperationFailure {
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

extension EmailVerificationStartAPIFailure {
    fileprivate func toOperationFailure() -> EmailVerificationOperationFailure {
        switch self {
        case .badRequest(.invalidArgument(let errorCode, let message)),
            .badRequest(.unknown(let errorCode, let message)):
            return .input(.invalidRequest(errorCode: errorCode, message: message, apiFailure: self))
        case .badRequest(.invalidLoginID(let errorCode, let message, let loginID, let regex)):
            return .input(.invalidLoginID(errorCode: errorCode, message: message, loginID: loginID, regex: regex, apiFailure: self))
        case .badRequest(.unsupportedLoginIDType(let errorCode, let message)):
            return .input(.unsupportedLoginIDType(errorCode: errorCode, message: message, apiFailure: self))
        case .badRequest(.missingChannel(let errorCode, let message, let loginID)):
            return .integration(.missingChannel(errorCode: errorCode, message: message, loginID: loginID, apiFailure: self))
        case .forbidden(let errorCode, let message):
            return .access(.forbidden(errorCode: errorCode, message: message, apiFailure: self))
        case .userNotFound(let errorCode, let message):
            return .access(.userNotFound(errorCode: errorCode, message: message, apiFailure: self))
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

extension EmailVerificationCompleteAPIFailure {
    fileprivate func toOperationFailure() -> EmailVerificationOperationFailure {
        switch self {
        case .badRequest(.invalidArgument(let errorCode, let message)),
            .badRequest(.unknown(let errorCode, let message)):
            return .input(.invalidRequest(errorCode: errorCode, message: message, apiFailure: self))
        case .badRequest(.wrongCode):
            return .unexpected(errorCode: errorCode, message: "WrongCode must be handled as active UI state", apiFailure: self)
        case .badRequest(.invalidChallenge(let errorCode, let message, let challengeID)):
            return .challenge(.invalid(errorCode: errorCode, message: message, challengeID: challengeID, apiFailure: self))
        case .badRequest(.maximumAttemptsReached(let errorCode, let message, let challengeID)):
            return .challenge(.maximumAttemptsReached(errorCode: errorCode, message: message, challengeID: challengeID, apiFailure: self))
        case .forbidden(let errorCode, let message):
            return .access(.forbidden(errorCode: errorCode, message: message, apiFailure: self))
        case .unexpected(let errorCode, let message, let underlyingError):
            return .unexpected(errorCode: errorCode, message: message, apiFailure: self, underlyingError: underlyingError)
        }
    }
}

extension EmailVerificationResendAPIFailure {
    fileprivate func toOperationFailure() -> EmailVerificationOperationFailure {
        switch self {
        case .badRequest(.invalidArgument(let errorCode, let message)),
            .badRequest(.unknown(let errorCode, let message)):
            return .input(.invalidRequest(errorCode: errorCode, message: message, apiFailure: self))
        case .badRequest(.maximumResendAttemptsReached):
            return .unexpected(
                errorCode: errorCode,
                message: "MaximumResendAttemptsReached must be handled as active UI state",
                apiFailure: self
            )
        case .badRequest(.invalidChallenge(let errorCode, let message, let challengeID)):
            return .challenge(.invalid(errorCode: errorCode, message: message, challengeID: challengeID, apiFailure: self))
        case .failedDependency(.providerFailed(let errorCode, let message, _)):
            return .integration(.providerFailed(errorCode: errorCode, message: message, apiFailure: self))
        case .failedDependency(.missingProvider(let errorCode, let message, let capability, _)):
            return .integration(.missingProvider(errorCode: errorCode, message: message, capability: capability, apiFailure: self))
        case .unexpected(let errorCode, let message, let underlyingError):
            return .unexpected(errorCode: errorCode, message: message, apiFailure: self, underlyingError: underlyingError)
        }
    }
}

extension Optional where Wrapped == LoginID {
    fileprivate func isSupportedVerificationTarget(_ targetType: LoginIDType, loginIDHintID: String?) -> Bool {
        guard let loginID = self else { return true }
        if loginID.type == targetType { return true }
        if loginID.type == .userName {
            return !(loginIDHintID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
        return false
    }
}
