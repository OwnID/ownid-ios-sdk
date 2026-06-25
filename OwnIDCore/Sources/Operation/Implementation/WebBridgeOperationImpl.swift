import Foundation
import WebKit

/// Owns the iOS WebBridge operation state machine.
///
/// Start resolves WebView content and options in caller, server-config, local-runtime, then SDK-default order; validates
/// the resolved page origin; and publishes a ``WebBridgeUIState`` for SDK-managed `WKWebView` presentation.
///
/// The state machine settles once. Successful terminal hosted callbacks settle with ``OperationResult/success(_:)``,
/// immediate or delayed UI startup failures and WebView runtime errors settle with ``OperationResult/failure(_:)``, and
/// user close, WebView detach, abort, and SDK shutdown settle with ``OperationResult/canceled(_:)``. Completion releases
/// controller ownership.
internal final class WebBridgeOperationImpl: WebBridgeOperation, @unchecked Sendable {
    enum Event: Sendable {
        enum UIEvent: Sendable { case close, error((any Error)?, String?), cancel(Reason) }
        case start(WebBridgeOperationParams?)
        case ui(UIEvent)
        case abort(Reason)
        case complete(OperationResult<Void, WebBridgeOperationFailure>)
    }

    internal let operationType: OperationType
    internal let operationID: OperationID
    private let operationRegistry: OperationRegistryImpl
    private let configuration: any OwnIDConfiguration
    private let appConfigProvider: any AppConfigProvider
    private let localInfo: any LocalInfo
    private let ui: any WebBridgeUI
    private let webBridge: any WebBridge
    private let taskScope: TaskScope
    private let logger: OwnIDLogRouter?
    private let unsatisfiedDependencies: [String]?

    private let stream = OperationEventStream<Event>()
    @MainActor private var shouldSuppressDetachAbort = false

    internal lazy var controller: WebBridgeOperationControllerImpl = {
        let controller = WebBridgeOperationControllerImpl(operationID: operationID) { [weak self] reason in
            guard let self else { return }
            taskScope.spawn { await self.stream.yield(.abort(reason)) }
        }
        controller._attachOwner(self)
        return controller
    }()

    init(
        operationType: OperationType,
        operationRegistry: OperationRegistryImpl,
        configuration: any OwnIDConfiguration,
        appConfigProvider: any AppConfigProvider,
        localInfo: any LocalInfo,
        ui: any WebBridgeUI,
        webBridge: any WebBridge,
        taskScope: TaskScope,
        logger: OwnIDLogRouter?,
        unsatisfiedDependencies: [String]? = nil
    ) {
        self.operationType = operationType
        self.operationID = operationType.createOperationID()
        self.operationRegistry = operationRegistry
        self.configuration = configuration
        self.appConfigProvider = appConfigProvider
        self.localInfo = localInfo
        self.ui = ui
        self.webBridge = webBridge
        self.taskScope = taskScope
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
                    let cur = await MainActor.run { self.controller.state }
                    if case .created = cur {
                        await MainActor.run { self.operationRegistry.register(controller: self.controller) }

                        let params = params ?? WebBridgeOperationParams()
                        let registeredPlugins = self.webBridge.plugins.snapshot()
                        let elitePlugin = registeredPlugins.first { $0 is WebBridgeElitePlugin } as? WebBridgeElitePlugin

                        elitePlugin?.addEventWrappers(params.eventWrappers)
                        elitePlugin?.setWrapperSideEffect { [weak self] wrapper in
                            guard let self, wrapper.isTerminal else { return }
                            taskScope.spawn { await self.stream.yield(.ui(.close)) }
                        }

                        let appConfig: AppConfig
                        do {
                            appConfig = try await self.appConfigProvider.getOrFetchConfig()
                        } catch is CancellationError {
                            return
                        } catch {
                            return
                        }
                        let baseUrl = params.options?.baseUrl ?? appConfig.webView?.baseUrl ?? WebBridgeUIDefaults.webViewURL
                        params.onBaseUrlResolved?(baseUrl)
                        let html = params.options?.html ?? appConfig.webView?.html ?? WebBridgeUIDefaults.html(for: self.configuration)
                        let userAgent = params.options?.userAgent ?? self.localInfo.userAgent
                        let webViewIsInspectable = params.options?.webViewIsInspectable ?? self.localInfo.isDebuggable
                        let backgroundColor = params.options?.backgroundColor
                        let webViewConfiguration = WebBridgeWebViewConfiguration(
                            limitsNavigationsToAppBoundDomains: params.options?.limitsNavigationsToAppBoundDomains ?? false
                        )
                        guard let pageOrigin = OriginNormalizer.origin(fromAbsolutePageURL: baseUrl) else {
                            await self.stream.yield(
                                .complete(
                                    .failure(
                                        WebBridgeOperationFailure.precondition(
                                            errorCode: .unknown,
                                            message: "Invalid baseUrl for WebBridge origin derivation: \(baseUrl)"
                                        )
                                    )
                                )
                            )
                            continue
                        }

                        let uiRef = self.ui
                        let bridge = self.webBridge
                        let stream = self.stream
                        let emitDetachAbort: @Sendable () -> Void = { [taskScope, stream] in
                            taskScope.spawn { [stream] in
                                await stream.yield(.abort(.userClose(details: "Elite UI detached")))
                            }
                        }
                        let detach: @MainActor @Sendable () -> Void = {
                            bridge.detach()
                            guard self.shouldSuppressDetachAbort == false else { return }
                            guard case .completed = self.controller.state else {
                                self.logger?.logI(
                                    source: self,
                                    prefix: "Event.Abort",
                                    message: "WebBridge UI detached before operation completed"
                                )
                                emitDetachAbort()
                                return
                            }
                        }
                        let startError = await MainActor.run {
                            self.shouldSuppressDetachAbort = false
                            return uiRef.start(
                                controller: self.controller,
                                webViewConfiguration: webViewConfiguration,
                                onDetach: detach
                            ) { [weak self] error in
                                guard let self else { return }
                                self.shouldSuppressDetachAbort = true
                                self.logger?.logW(
                                    source: self,
                                    prefix: "Event.Start",
                                    message: "UI start error: \(error.message)",
                                    cause: error.underlyingError
                                )
                                taskScope.spawn {
                                    await self.stream.yield(.complete(.failure(.ui(error))))
                                }
                            }
                        }
                        if let startError {
                            self.logger?.logW(
                                source: self,
                                prefix: "Event.Start",
                                message: "UI start error: \(startError.message)",
                                cause: startError.underlyingError
                            )
                            await self.stream.yield(.complete(.failure(.ui(startError))))
                            continue
                        }

                        let uiState = WebBridgeUIState(
                            baseUrl: baseUrl,
                            html: html,
                            userAgent: userAgent,
                            webViewIsInspectable: webViewIsInspectable,
                            backgroundColor: backgroundColor,
                            doWebViewBridgeInject: { [weak self] webView in
                                guard let self else { return }
                                let pageOriginRules: Set<String> = [pageOrigin]
                                if let error = self.webBridge.attach(webView: webView, allowedOriginRules: pageOriginRules) {
                                    self.logger?.logW(
                                        source: self,
                                        prefix: "WebBridge.inject",
                                        message: "Injection failed: \(error.localizedDescription)",
                                        cause: error
                                    )
                                    Task {
                                        await self.stream.yield(
                                            .ui(.error(error, "WebBridge injection failed: \(error.localizedDescription)"))
                                        )
                                    }
                                }
                            },
                            onWebViewTerminalError: { [weak self] error, message in
                                guard let self else { return }
                                self.logger?.logW(
                                    source: self,
                                    prefix: "Event.Start",
                                    message: message ?? (error.map { String(describing: $0) } ?? "WebBridge terminal error"),
                                    cause: error
                                )
                                taskScope.spawn { await self.stream.yield(.ui(.error(error, message))) }
                            },
                            onWebViewCancel: { [weak self] reason in
                                guard let self else { return }
                                taskScope.spawn { await self.stream.yield(.ui(.cancel(reason))) }
                            }
                        )
                        await MainActor.run { self.controller.state = .active(uiState: uiState) }
                    }

                case .ui(let uiEvent):
                    let state = await MainActor.run { self.controller.state }
                    switch state {
                    case .created:
                        let error = self.unexpectedEventError(eventDescription: ".ui", state: state)
                        await self.stream.yield(.complete(.failure(error)))
                    case .active:
                        switch uiEvent {
                        case .close: await self.stream.yield(.complete(.success(())))
                        case .error(let error, let message):
                            let uiError = WebBridgeOperationFailure.UI(
                                errorCode: .unknown,
                                message: message ?? error.map { String(describing: $0) } ?? "WebBridge UI failed",
                                underlyingError: error.map { $0.asSendableError() }
                            )
                            await self.stream.yield(.complete(.failure(.ui(uiError))))
                        case .cancel(let reason): await self.stream.yield(.complete(.canceled(reason)))
                        }

                    case .completed:
                        break
                    }

                case .abort(let reason):
                    let state = await MainActor.run { self.controller.state }
                    switch state {
                    case .created: await self.stream.yield(.complete(.canceled(reason)))
                    case .active: await self.stream.yield(.complete(.canceled(reason)))
                    case .completed: break
                    }

                case .complete(let result):
                    let didSettle = await self.markCompletedIfNeeded(result)
                    guard didSettle else { break }
                    await MainActor.run { self.operationRegistry.unregister(id: self.operationID) }
                    self.controller._releaseOwner()

                    result
                        .onSuccess { _ in self.controller.complete(()) }
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
    internal func start(params: WebBridgeOperationParams? = nil) -> any OperationController<Void, WebBridgeOperationFailure> {
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
        if let params, !(params is WebBridgeOperationParams) {
            return .unavailable("Unsupported params type: \(String(describing: type(of: params)))")
        }
        return .available
    }

    private func unexpectedEventError(eventDescription: String, state: WebBridgeOperationState) -> WebBridgeOperationFailure {
        .unexpected(message: "\(Self.self): Unexpected event [\(eventDescription)] for state [\(state)]")
    }

    @MainActor
    private func markCompletedIfNeeded(_ result: OperationResult<Void, WebBridgeOperationFailure>) -> Bool {
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
            await MainActor.run { self.operationRegistry.unregister(id: self.operationID) }
            self.controller._releaseOwner()
            self.controller.cancel(reason)
            await self.stream.finish()
        }
    }
}

extension WebBridgeOperationImpl {

    internal static func create(resolver: any DIContainerResolver) -> any WebBridgeOperation {
        do {
            return WebBridgeOperationImpl(
                operationType: .webBridge,
                operationRegistry: try resolver.getOrThrow(type: (any OperationRegistry).self) as! OperationRegistryImpl,
                configuration: try resolver.getOrThrow(type: (any OwnIDConfiguration).self),
                appConfigProvider: try resolver.getOrThrow(type: (any AppConfigProvider).self),
                localInfo: try resolver.getOrThrow(type: (any LocalInfo).self),
                ui: try resolver.getOrThrow(type: (any WebBridgeUI).self),
                webBridge: try resolver.getOrThrow(type: (any WebBridge).self),
                taskScope: try resolver.getOrThrow(type: TaskScope.self),
                logger: resolver.getOrNil(type: OwnIDLogRouter.self),
                unsatisfiedDependencies: resolver.getUnsatisfiedDependencies(for: (any WebBridgeOperation).self)
            )
        } catch {
            return Failed(error: error)
        }
    }
}

private final class Failed: WebBridgeOperation, @unchecked Sendable {
    let operationType: OperationType = .webBridge
    let operationID: OperationID = OperationType.webBridge.createOperationID()
    private let controllerImpl: WebBridgeOperationControllerImpl
    private let failure: WebBridgeOperationFailure

    init(error: any Error) {
        let failure = WebBridgeOperationFailure.unexpected(message: String(describing: error), underlyingError: error.asSendableError())
        let controller = WebBridgeOperationControllerImpl(
            operationID: operationID,
            onUserAborted: { _ in },
            initialState: .completed(result: .failure(failure))
        )
        self.failure = failure
        controller.fail(failure)
        self.controllerImpl = controller
    }

    @discardableResult
    func start(params: WebBridgeOperationParams? = nil) -> any OperationController<Void, WebBridgeOperationFailure> {
        controllerImpl
    }

    func availability(params: (any CapabilityParams)?) async -> Availability {
        .unavailable(failure.message)
    }
}

internal final class WebBridgeOperationControllerImpl:
    OperationControllerImpl<Void, WebBridgeOperationFailure>, WebBridgeOperationController, @unchecked Sendable
{
    @MainActor @BroadcastedState private var currentState: WebBridgeOperationState = .created

    internal init(
        operationID: OperationID,
        onUserAborted: @escaping @Sendable (Reason) -> Void,
        initialState: WebBridgeOperationState = .created
    ) {
        self._currentState = BroadcastedState(wrappedValue: initialState)
        super.init(operationID: operationID, onUserAborted: onUserAborted)
    }

    @MainActor internal var state: WebBridgeOperationState {
        get { currentState }
        set { currentState = newValue }
    }

    @MainActor
    func stateStream() -> AsyncStream<WebBridgeOperationState> {
        _currentState.stream()
    }
}
