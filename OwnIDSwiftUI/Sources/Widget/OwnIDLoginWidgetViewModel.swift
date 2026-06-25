import Foundation
@_spi(OwnIDInternal) import OwnIDCore

/// Manages Boost login widget state and effects.
///
/// Public by design so apps can either:
/// - let ``OwnIDLoginWidget`` own the view model lifecycle, or
/// - own and reuse the same view model in custom widget UIs.
///
/// The view model owns Boost login flow execution and exposes renderable state plus one-off effects. The app owns
/// collecting those effects while its widget UI is active and mapping them to session, navigation, cancel, or error
/// handling.
@MainActor
public final class OwnIDLoginWidgetViewModel {
    /// Current state that can be rendered by a widget view.
    public struct UIState: Equatable, Sendable {
        /// Whether a login flow is currently running.
        public let isRunning: Bool

        /// Creates a UI state value.
        ///
        /// - Parameter isRunning: Whether the login flow is currently running.
        public init(isRunning: Bool = false) {
            self.isRunning = isRunning
        }
    }

    /// One-off effects emitted by the login flow.
    public enum UIEffect: Sendable {
        /// Emitted when the login flow completes successfully.
        case login(BoostFlowLoginResponse)
        /// Emitted when the login flow fails or cannot be started.
        case error(BoostLoginFlowFailure)
        /// Emitted when the login flow is canceled.
        case canceled(Reason)
    }

    /// Current renderable state value.
    public private(set) var uiState: UIState = UIState()

    /// Stream of renderable state updates.
    ///
    /// Each new subscriber receives the current value immediately. State describes widget rendering only; it is not
    /// a durable app session state.
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

    private enum State {
        case idle
        case running
    }

    private enum FlowStarter {
        case defaultInstance(InstanceName)
        case custom(@MainActor @Sendable (BoostFlowContext) throws -> any BoostLoginFlowController)
    }

    private let flowStarter: FlowStarter
    private var state: State = .idle {
        didSet {
            let nextState = UIState(isRunning: state == .running)
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
    private var currentController: (any BoostLoginFlowController)?
    private var settleTask: Task<Void, Never>?

    /// Creates a login widget view model with a custom login starter.
    ///
    /// Use this initializer when your app needs to inject a custom flow starter, for example in custom widget UI. The
    /// starter owns any app-specific flow wiring and should return a controller that settles exactly once.
    ///
    /// - Parameter boostLoginFlowStarter: Closure that starts login for the provided flow context.
    public init(
        boostLoginFlowStarter: @escaping @MainActor @Sendable (BoostFlowContext) throws -> any BoostLoginFlowController
    ) {
        self.flowStarter = .custom(boostLoginFlowStarter)
    }

    /// Creates a login widget view model that uses the default OwnID login flow for `instanceName`.
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
        currentController?.abort(reason: .userClose(details: "Login widget deinitialized"))
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

    /// Starts the login flow when the view model is idle.
    ///
    /// Calls while a flow is already running are ignored. Empty or blank `loginID` values are normalized to `nil`.
    /// The flow context uses the widget-button source.
    ///
    /// Successful completion emits ``UIEffect/login(_:)``. Flow cancellation emits ``UIEffect/canceled(_:)``. Flow
    /// failures and starter errors emit ``UIEffect/error(_:)`` and return the view model to idle.
    ///
    /// - Parameter loginID: Optional raw login ID to pass into the flow context.
    public func startFlow(loginID: String?) {
        guard state != .running else { return }
        state = .running

        let normalizedLoginID = Self.normalizeLoginID(loginID)

        let flowContext = BoostFlowContext {
            if let normalizedLoginID {
                $0.loginID(normalizedLoginID)
            }
            $0.source = .widgetButton
        }

        do {
            let controller: any BoostLoginFlowController
            switch flowStarter {
            case .defaultInstance(let instanceName):
                guard let instance = OwnID.instanceIfPresent(instanceName: instanceName) else {
                    emitUiEffect(
                        .error(
                            BoostLoginFlowFailure.unexpected(
                                errorCode: .integrationError,
                                message: "No OwnID instance with name '\(instanceName.value)'"
                            )
                        )
                    )
                    state = .idle
                    return
                }
                controller = instance.flows.boost.login.start(flowContext)
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
                        .onSuccess { response in self.emitUiEffect(.login(response)) }
                        .onCanceled { reason in self.emitUiEffect(.canceled(reason)) }
                        .onError { error in self.emitUiEffect(.error(error)) }
                    self.state = .idle
                }
            }
        } catch {
            currentController = nil
            settleTask = nil

            let message = error.localizedDescription.isEmpty ? "Failed to start login flow" : error.localizedDescription
            let wrappedError = BoostLoginFlowFailure.unexpected(
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
