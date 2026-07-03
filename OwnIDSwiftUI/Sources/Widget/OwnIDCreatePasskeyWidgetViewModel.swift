import Foundation
@_spi(OwnIDInternal) import OwnIDCore

/// Manages Boost create-passkey widget state and effects.
///
/// Public by design so apps can either:
/// - let ``OwnIDCreatePasskeyWidget`` own the view model lifecycle, or
/// - own and reuse the same view model in custom widget UIs.
///
/// The view model owns Boost create-passkey flow execution and exposes renderable state plus one-off effects. The app
/// owns collecting those effects while its widget UI is active and mapping them to session, navigation, registration,
/// reset, cancel, or error handling.
///
/// The view model keeps the latest create-passkey success in memory while it is alive so the widget can keep its
/// completion state visible and later restore or clear that state as the login ID changes. It does not persist the
/// response outside the view model.
@MainActor
public final class OwnIDCreatePasskeyWidgetViewModel {
    /// Current state that can be rendered by a widget view.
    public struct UIState: Equatable, Sendable {
        /// Whether a create-passkey flow is currently running.
        public let isRunning: Bool
        /// Whether the completion checkmark should be visible.
        public let showCheckmark: Bool

        /// Creates a UI state value.
        ///
        /// - Parameters:
        ///   - isRunning: Whether the create-passkey flow is currently running.
        ///   - showCheckmark: Whether completion checkmark UI should be shown.
        public init(isRunning: Bool = false, showCheckmark: Bool = false) {
            self.isRunning = isRunning
            self.showCheckmark = showCheckmark
        }
    }

    /// One-off effects emitted by the create-passkey flow.
    public enum UIEffect: Sendable {
        /// Emitted when previously completed create-passkey UI should be cleared.
        case resetRequested
        /// Emitted when the flow completes by logging the user in instead of creating a new passkey.
        case login(BoostFlowLoginResponse)
        /// Emitted when the flow creates a new passkey.
        case createPasskey(BoostFlowCreatePasskeyResponse)
        /// Emitted when the create-passkey flow fails or cannot be started.
        case error(BoostCreatePasskeyFlowFailure)
        /// Emitted when the create-passkey flow is canceled.
        case canceled(Reason)
    }

    /// Current renderable state value.
    public private(set) var uiState: UIState = UIState()

    /// Stream of renderable state updates.
    ///
    /// Each new subscriber receives the current value immediately. State describes widget rendering only; it is not
    /// a durable app registration state.
    public var uiStateStream: AsyncStream<UIState> {
        AsyncStream { continuation in
            let id = UUID()
            uiStateContinuations[id] = continuation
            continuation.yield(uiState)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.uiStateContinuations.removeValue(forKey: id)
                }
            }
        }
    }

    /// Stream of one-off callback effects.
    ///
    /// Only the latest subscriber stays active. Creating a new stream finishes the previous one. Effects emitted while
    /// no subscriber is active are buffered and delivered when a new subscriber starts collecting. Collect while the
    /// widget UI is active and map each effect to the corresponding screen callback.
    public var uiEffects: AsyncStream<UIEffect> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let token = UUID()
            uiEffectContinuation?.finish()
            uiEffectContinuation = continuation
            uiEffectToken = token
            drainUiEffectQueue()
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    guard self.uiEffectToken == token else { return }
                    self.uiEffectContinuation = nil
                    self.uiEffectToken = nil
                }
            }
        }
    }

    private enum State: Equatable {
        case idle
        case running
        case ready(BoostFlowCreatePasskeyResponse)
        case stored(BoostFlowCreatePasskeyResponse)
    }

    private enum FlowStarter {
        case defaultInstance(InstanceName)
        case custom(@MainActor @Sendable (BoostFlowContext) throws -> any BoostCreatePasskeyFlowController)
    }

    private let flowStarter: FlowStarter
    private var state: State = .idle {
        didSet {
            let nextState = UIState(
                isRunning: state == .running,
                showCheckmark: {
                    if case .ready = state { return true }
                    return false
                }()
            )
            guard uiState != nextState else { return }
            uiState = nextState
            for continuation in uiStateContinuations.values {
                continuation.yield(nextState)
            }
        }
    }
    private var uiStateContinuations: [UUID: AsyncStream<UIState>.Continuation] = [:]
    private var uiEffectQueue: [UIEffect] = []
    private var uiEffectContinuation: AsyncStream<UIEffect>.Continuation?
    private var uiEffectToken: UUID?
    private var currentController: (any BoostCreatePasskeyFlowController)?
    private var settleTask: Task<Void, Never>?

    /// Creates a create-passkey widget view model with a custom flow starter.
    ///
    /// Use this initializer when your app needs to inject a custom flow starter, for example in custom widget UI. The
    /// starter owns any app-specific flow wiring and should return a controller that settles exactly once.
    ///
    /// - Parameter boostCreatePasskeyFlowStarter: Closure that starts create-passkey for the provided flow context.
    public init(
        boostCreatePasskeyFlowStarter: @escaping @MainActor @Sendable (BoostFlowContext) throws -> any BoostCreatePasskeyFlowController
    ) {
        self.flowStarter = .custom(boostCreatePasskeyFlowStarter)
    }

    /// Creates a create-passkey widget view model that uses the default OwnID create-passkey flow for `instanceName`.
    ///
    /// - Parameter instanceName: Instance used for default flow provisioning. Defaults to `.default`.
    public convenience init(instanceName: InstanceName = .default) {
        self.init(flowStarter: .defaultInstance(instanceName))
    }

    private init(flowStarter: FlowStarter) {
        self.flowStarter = flowStarter
    }

    deinit {
        settleTask?.cancel()
        currentController?.abort(reason: .userClose(details: "Create-passkey widget deinitialized"))
        currentController = nil

        for continuation in uiStateContinuations.values {
            continuation.finish()
        }
        uiStateContinuations.removeAll()

        uiEffectContinuation?.finish()
        uiEffectContinuation = nil
        uiEffectToken = nil
        uiEffectQueue.removeAll()
    }

    /// Keeps the in-memory create-passkey completion state aligned with the current login ID.
    ///
    /// The view model emits ``UIEffect/resetRequested`` when the surrounding UI should clear the current completion
    /// state, and emits ``UIEffect/createPasskey(_:)`` when it restores a remembered completion state for the
    /// matching login ID. Calls while a flow is running are ignored.
    ///
    /// - Parameter loginID: Current raw login ID input. Empty or blank values are treated as `nil`.
    public func onLoginIDChanged(_ loginID: String?) {
        guard state != .running else { return }

        let normalizedLoginID = Self.normalizeLoginID(loginID)

        switch state {
        case .ready(let response):
            if normalizedLoginID != response.loginID.id {
                emitUiEffect(.resetRequested)
                state = .stored(response)
            }
        case .stored(let response):
            if normalizedLoginID == response.loginID.id {
                emitUiEffect(.createPasskey(response))
                state = .ready(response)
            }
        case .idle, .running:
            break
        }
    }

    /// Starts the create-passkey flow and coordinates in-memory completion state for the current login ID.
    ///
    /// Calls while a flow is already running are ignored. Empty or blank `loginID` values are normalized to `nil`.
    /// New flow starts use the widget-button source.
    ///
    /// Depending on the current state, this method can emit ``UIEffect/resetRequested`` to clear the existing
    /// completion UI, emit ``UIEffect/createPasskey(_:)`` to restore remembered completion for the same login ID, or
    /// start a new flow.
    ///
    /// Flow cancellation emits ``UIEffect/canceled(_:)``. Flow failures and starter errors emit
    /// ``UIEffect/error(_:)`` and return the view model to idle. Successful flow results emit either
    /// ``UIEffect/login(_:)`` or ``UIEffect/createPasskey(_:)``.
    ///
    /// - Parameter loginID: Optional raw login ID to pass into the flow context.
    public func startFlow(loginID: String?) {
        let normalizedLoginID = Self.normalizeLoginID(loginID)

        switch state {
        case .running:
            return
        case .ready(let response):
            emitUiEffect(.resetRequested)
            state = .stored(response)
            return
        case .stored(let response):
            if normalizedLoginID == response.loginID.id {
                emitUiEffect(.createPasskey(response))
                state = .ready(response)
                return
            }
            state = .idle
        case .idle:
            break
        }

        state = .running

        let flowContext = BoostFlowContext {
            if let normalizedLoginID {
                $0.loginID(normalizedLoginID)
            }
            $0.source = .widgetButton
        }

        do {
            let controller: any BoostCreatePasskeyFlowController
            switch flowStarter {
            case .defaultInstance(let instanceName):
                guard let instance = OwnID.instanceIfPresent(instanceName: instanceName) else {
                    emitUiEffect(
                        .error(
                            BoostCreatePasskeyFlowFailure.unexpected(
                                errorCode: .integrationError,
                                message: "No OwnID instance with name '\(instanceName.value)'"
                            )
                        )
                    )
                    state = .idle
                    return
                }
                controller = instance.flows.boost.createPasskey.start(flowContext)
            case .custom(let starter):
                controller = try starter(flowContext)
            }
            currentController = controller

            settleTask?.cancel()
            settleTask = Task { [weak self] in
                let result = await controller.whenSettled()
                await MainActor.run {
                    guard let self else { return }
                    self.currentController = nil
                    self.settleTask = nil

                    result
                        .onCanceled { reason in
                            self.emitUiEffect(.canceled(reason))
                            self.state = .idle
                        }
                        .onError { error in
                            self.emitUiEffect(.error(error))
                            self.state = .idle
                        }

                    if let response = result.getOrNil() {
                        switch response {
                        case .login(let loginResponse):
                            self.emitUiEffect(.login(loginResponse))
                            self.state = .idle
                        case .createPasskey(let createPasskeyResponse):
                            self.emitUiEffect(.createPasskey(createPasskeyResponse))
                            self.state = .ready(createPasskeyResponse)
                        }
                    }
                }
            }
        } catch {
            currentController = nil
            settleTask = nil

            let message = error.localizedDescription.isEmpty ? "Failed to start create passkey flow" : error.localizedDescription
            let wrappedError = BoostCreatePasskeyFlowFailure.unexpected(
                errorCode: .integrationError,
                message: message,
                underlyingError: error as NSError
            )

            emitUiEffect(.error(wrappedError))
            state = .idle
        }
    }

    /// Requests cancellation of the running flow, if any.
    ///
    /// This method is a no-op when no flow is running. When a controller is active, the eventual effect is determined
    /// by the flow settlement, usually ``UIEffect/canceled(_:)`` for a cancellation result.
    ///
    /// - Parameter reason: Cancellation reason propagated to the flow result.
    public func abort(reason: Reason = .userClose(details: nil)) {
        currentController?.abort(reason: reason)
    }

    private static func normalizeLoginID(_ loginID: String?) -> String? {
        guard let loginID else { return nil }
        let normalizedLoginID = loginID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedLoginID.isEmpty else { return nil }
        return normalizedLoginID
    }

    private func emitUiEffect(_ effect: UIEffect) {
        uiEffectQueue.append(effect)
        drainUiEffectQueue()
    }

    private func drainUiEffectQueue() {
        guard let continuation = uiEffectContinuation else { return }

        while !uiEffectQueue.isEmpty {
            let nextEffect = uiEffectQueue[0]
            switch continuation.yield(nextEffect) {
            case .enqueued, .dropped:
                uiEffectQueue.removeFirst()
            case .terminated:
                uiEffectContinuation = nil
                uiEffectToken = nil
                return
            @unknown default:
                uiEffectQueue.removeFirst()
            }
        }
    }
}
