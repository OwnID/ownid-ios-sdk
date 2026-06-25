import Foundation

/// Runtime boundary between Elite flow controller semantics and the SDK-managed WebBridge operation.
///
/// Maintainer contract: one instance accepts one start and publishes one terminal ``FlowResult``. Hosted
/// finish/native-action/error/close events settle as success after callbacks return; owner abort and shutdown settle as
/// cancellation with the provided or SDK-generated ``Reason``. Controller, WebBridge, and shutdown paths must not
/// publish multiple results for the same run.
internal final class EliteFlowImpl: EliteFlow, @unchecked Sendable {
    private let webBridgeOperation: (any WebBridgeOperation)?
    private let userJourney: (any UserJourney)?
    private let taskScope: TaskScope
    private let logger: OwnIDLogRouter?

    private lazy var actor: EliteFlowActor = {
        EliteFlowActor(
            webBridgeOperation: self.webBridgeOperation,
            userJourney: self.userJourney,
            taskScope: self.taskScope,
            logger: self.logger,
            onStateChange: { [weak self] newState in
                self?.taskScope.spawnOnMain { [weak self] in
                    await self?.handleStateChange(newState)
                }
            }
        )
    }()

    private let controllerLock = NSLock()
    private var controller: FlowController<Void, EliteFlowFailure>?
    private let completionLock = NSLock()
    private var didComplete = false
    private let activeAbortLock = NSLock()
    private var activeAbort: ((Reason) -> Void)?

    init(
        webBridgeOperation: (any WebBridgeOperation)?,
        userJourney: (any UserJourney)?,
        taskScope: TaskScope,
        logger: OwnIDLogRouter?
    ) {
        self.webBridgeOperation = webBridgeOperation
        self.userJourney = userJourney
        self.taskScope = taskScope
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
    func start(_ context: EliteFlowContext) -> any EliteFlowController {
        let controller = controllerLock.withLock {
            if let controller = self.controller { return controller }
            let newController = FlowController<Void, EliteFlowFailure>(
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

    @MainActor
    private func handleStateChange(_ newState: EliteFlowActor.State) async {
        guard let controller else { return }

        if case .active(let opController, _) = newState {
            // Keep owner-driven cancellation mapped to the active WebBridge controller while the WebView run is active.
            activeAbortLock.withLock {
                activeAbort = { reason in
                    opController.abort(reason: reason)
                }
            }
        }

        if case .completed(let result) = newState {
            // Completion is intentionally idempotent: hosted terminal callbacks, abort, and shutdown can race at the boundary.
            let shouldComplete = completionLock.withLock {
                if didComplete { return false }
                didComplete = true
                return true
            }
            activeAbortLock.withLock { activeAbort = nil }
            switch result {
            case .success:
                if shouldComplete {
                    userJourney?.completeFlow(.completed(nil))
                }
                controller.complete(())
            case .canceled(let reason):
                if shouldComplete {
                    userJourney?.completeFlow(
                        .error(
                            errorCode: .aborted,
                            source: "EliteFlowImpl.handleStateChange.canceled",
                            message: "Canceled with reason: \(reason.description)"
                        )
                    )
                }
                controller.cancel(reason)
            case .failure(let failure):
                if shouldComplete {
                    userJourney?.completeFlow(
                        .error(errorCode: failure.errorCode, source: "EliteFlowImpl.handleStateChange.failure", message: failure.message)
                    )
                }
                controller.fail(failure)
            }
        }
    }

    private func handleShutdown() {
        guard let controller else { return }
        // Shutdown maps the active WebBridge run to the same canceled result exposed by controller abort.
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
                    source: "EliteFlowImpl.handleShutdown.canceled",
                    message: "Canceled with reason: \(reason.description)"
                )
            )
        }
    }

    internal static func create(resolver: any DIContainerResolver) -> any EliteFlow {
        do {
            return EliteFlowImpl(
                webBridgeOperation: resolver.getOrNil(type: (any WebBridgeOperation).self),
                userJourney: resolver.getOrNil(type: (any UserJourney).self),
                taskScope: try resolver.getOrThrow(type: TaskScope.self),
                logger: resolver.getOrNil(type: OwnIDLogRouter.self)
            )
        } catch {
            return Failed(error: error)
        }
    }
}

private final class Failed: EliteFlow, @unchecked Sendable {
    private let controller: FlowController<Void, EliteFlowFailure>

    init(error: any Error) {
        controller = FlowController<Void, EliteFlowFailure>(onUserAborted: { _ in })
        controller.fail(.unexpected(message: error.localizedDescription, underlyingError: error))
    }

    @discardableResult
    func start(_ context: EliteFlowContext) -> any EliteFlowController {
        controller
    }
}

private actor EliteFlowActor {

    enum State: @unchecked Sendable {
        case created
        case active(controller: any WebBridgeOperationController, context: EliteFlowContext)
        case completed(result: FlowResult<Void, EliteFlowFailure>)
    }

    enum Event: Sendable {
        case start(EliteFlowContext)
        case abort(Reason)
        case webBridgeOpResult(OperationID, OperationResult<Void, WebBridgeOperationFailure>)
    }

    private var state: State = .created { didSet { onStateChange(state) } }
    private let webBridgeOperation: (any WebBridgeOperation)?
    private let logger: OwnIDLogRouter?
    private let userJourney: (any UserJourney)?
    private let taskScope: TaskScope
    private let onStateChange: @Sendable (State) -> Void
    private let eventContinuation: AsyncStream<Event>.Continuation

    init(
        webBridgeOperation: (any WebBridgeOperation)?,
        userJourney: (any UserJourney)?,
        taskScope: TaskScope,
        logger: OwnIDLogRouter?,
        onStateChange: @escaping @Sendable (State) -> Void
    ) {
        self.webBridgeOperation = webBridgeOperation
        self.logger = logger
        self.userJourney = userJourney
        self.taskScope = taskScope
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
                if case .completed = newState { break }
            }
        } catch {
            logger?.logW(source: self, prefix: "runEventLoop", message: "Flow error \(error)", cause: error)
            self.state = .completed(
                result: .failure(.unexpected(message: "Flow error in Elite", underlyingError: error))
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

        case (.created, .start(let flowContext)):
            return try await handleStart(context: flowContext)

        case (.active(let controller, _), .webBridgeOpResult(let operationID, let result)):
            guard controller.operationID == operationID else { return state }
            switch result {
            case .success:
                return .completed(result: .success(()))
            case .canceled(let reason):
                return .completed(result: .canceled(reason))
            case .failure(let failure):
                return .completed(
                    result: .failure(
                        .operationFailed(
                            errorCode: failure.errorCode,
                            message: "Elite operation failed: \(failure.message)",
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

    private func handleStart(context: EliteFlowContext) async throws -> State {
        await userJourney?.startFlow(name: "elite", source: .elite, traceParent: nil)
        guard let webBridgeOperation = webBridgeOperation else {
            return .completed(
                result: .failure(.operationFailed(errorCode: .integrationError, message: "WebBridgeOperation unavailable"))
            )
        }

        let eventWrappers = context.eventsWrappers
        // Always provide no-op hosted terminal handlers so omitted app callbacks still close and settle natively.
        let wrappers =
            eventWrappers
            + [
                eventWrappers.contains { $0 is OnFinishWrapper } ? nil : OnFinishWrapper.empty as (any WebBridgeOperationEventWrapper)?,
                eventWrappers.contains { $0 is OnErrorWrapper } ? nil : OnErrorWrapper.empty as (any WebBridgeOperationEventWrapper)?,
                eventWrappers.contains { $0 is OnCloseWrapper } ? nil : OnCloseWrapper.empty as (any WebBridgeOperationEventWrapper)?,
            ].compactMap { $0 }

        let controller = webBridgeOperation.start(
            params: WebBridgeOperationParams(
                options: context.options,
                eventWrappers: wrappers,
                onBaseUrlResolved: { [userJourney, taskScope = self.taskScope] url in
                    taskScope.spawn { await userJourney?.setReferer(url) }
                }
            )
        )
        guard let webBridgeController = controller as? any WebBridgeOperationController else {
            return .completed(
                result: .failure(
                    .operationFailed(errorCode: .integrationError, message: "WebBridgeOperation returned incompatible controller type")
                )
            )
        }

        taskScope.spawn { [actor = self, operationID = controller.operationID] in
            let res = await controller.whenSettled()
            await actor.send(event: .webBridgeOpResult(operationID, res))
        }

        return .active(controller: webBridgeController, context: context)
    }
}
