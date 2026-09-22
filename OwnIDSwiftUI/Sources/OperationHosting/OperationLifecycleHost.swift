@_spi(OwnIDInternal) import OwnIDCore
import SwiftUI

/// Coordinates lifecycle for one app-hosted operation view.
///
/// The host renders from the scope captured by the app-hosted operation, keeping content and lifecycle tied to its
/// originating SDK instance. Embedded views abort when they disappear; app-owned containers defer owner-driven
/// cancellation until their final close signal, while content or instance errors can abort immediately. Settlement
/// completes the host and dismisses an app-owned container without converting an already-settled result into
/// cancellation.
internal struct OperationLifecycleHost<Controller: OperationController>: View {
    private let instanceName: InstanceName?
    private let operationController: Controller
    private let renderController: any OperationController
    @ObservedObject private var containerController: OwnIDUIContainerController
    private let usesAppContainer: Bool
    private let errorTextProvider: ((ErrorCode) -> String)?

    @State private var instanceResolver: (any DIContainerResolver)?
    @State private var lifecycleSession: OperationLifecycleSession<Controller>
    @State private var isSettled = false

    internal init(
        instanceName: InstanceName,
        instanceResolver: any DIContainerResolver,
        operationController: Controller,
        renderController: any OperationController,
        containerController: OwnIDUIContainerController? = nil,
        errorTextProvider: ((ErrorCode) -> String)? = nil
    ) {
        self.instanceName = instanceName
        self.operationController = operationController
        self.renderController = renderController
        let resolvedContainerController = containerController ?? OwnIDUIContainerController()
        self._containerController = ObservedObject(wrappedValue: resolvedContainerController)
        self.usesAppContainer = containerController != nil
        self.errorTextProvider = errorTextProvider
        self._instanceResolver = State(initialValue: instanceResolver)
        self._lifecycleSession = State(
            initialValue: OperationLifecycleSession(operationController: operationController, usesAppContainer: containerController != nil)
        )
    }

    internal init(
        instanceResolver: any DIContainerResolver,
        operationController: Controller,
        renderController: any OperationController,
        containerController: OwnIDUIContainerController,
        lifecycleSession: OperationLifecycleSession<Controller>? = nil,
        errorTextProvider: ((ErrorCode) -> String)? = nil
    ) {
        self.instanceName = nil
        self.operationController = operationController
        self.renderController = renderController
        self._containerController = ObservedObject(wrappedValue: containerController)
        self.usesAppContainer = true
        self.errorTextProvider = errorTextProvider
        self._instanceResolver = State(initialValue: instanceResolver)
        self._lifecycleSession = State(
            initialValue: lifecycleSession
                ?? OperationLifecycleSession(operationController: operationController, usesAppContainer: true)
        )
    }

    internal var body: some View {
        ZStack {
            Color.clear
                .frame(width: 0, height: 0)

            if let instanceResolver, !isSettled {
                OperationResolvedContentHost(
                    instanceResolver: instanceResolver,
                    operationController: renderController,
                    errorTextProvider: errorTextProvider,
                    isReadyForInitialFocus: usesAppContainer ? containerController.isInputReady : true,
                    abortOperation: { reason in
                        lifecycleSession.abort(reason: reason)
                    },
                    onMissingRenderer: {
                        instanceResolver.getOrNil(type: OwnIDLogRouter.self)?.logW(
                            source: Self.self,
                            prefix: "body",
                            message: "Missing UI renderer/provider for \(operationController.operationID.type)"
                        )
                        lifecycleSession.abort(
                            reason: .systemError(details: "Missing UI provider for \(operationController.operationID.type)")
                        )
                    }
                )
            }
        }
        .onAppear(perform: activateLifecycle)
        .onDisappear(perform: handleDisappear)
        .taskCompat(id: operationController.operationID) {
            await observeInstanceIfNeeded()
        }
    }

    @MainActor
    private func activateLifecycle() {
        lifecycleSession.activate(
            containerController: containerController,
            onSettled: { isSettled = true }
        )
    }

    @MainActor
    private func observeInstanceIfNeeded() async {
        guard let instanceName else { return }

        for await instanceContainer in OwnID.getInstanceContainerStream(instanceName) {
            if Task.isCancelled { break }

            guard instanceContainer != nil else {
                let logger = OwnID.getLogger() ?? OwnIDDefaultLogger.make()
                logger.log(
                    level: .warn,
                    className: "OwnIDOperationView",
                    message: "No instance found for \(instanceName.value)",
                    cause: nil
                )
                let reason = Reason.systemError(details: "OwnID SDK instance is no longer available")
                instanceResolver = nil
                lifecycleSession.abort(reason: reason)
                if usesAppContainer {
                    containerController.requestDismissWithoutAbort()
                }
                break
            }
        }
    }

    @MainActor
    private func handleDisappear() {
        guard usesAppContainer else {
            lifecycleSession.abort(reason: .userClose(details: "Operation view disappeared"))
            return
        }
    }
}

/// Owns the operation-side lifecycle for one rendered operation view.
///
/// Cancellation is idempotent. Embedded views cancel on disappearance, while app-owned containers defer owner-driven
/// cancellation until they report final close; settlement can instead request a dismissal without aborting the
/// operation.
@MainActor
internal final class OperationLifecycleSession<Controller: OperationController> {
    private let operationController: Controller
    private let usesAppContainer: Bool
    private var didAbort = false
    private var isActivated = false
    private var didSettle = false
    private var onSettledHandler: (@MainActor () -> Void)?
    private var settlementTask: Task<Void, Never>?

    internal init(operationController: Controller, usesAppContainer: Bool) {
        self.operationController = operationController
        self.usesAppContainer = usesAppContainer
    }

    deinit {
        settlementTask?.cancel()
    }

    internal func activate(containerController: OwnIDUIContainerController, onSettled: @escaping @MainActor () -> Void) {
        if didSettle {
            onSettled()
            return
        }
        onSettledHandler = onSettled
        guard !isActivated else { return }
        isActivated = true
        if usesAppContainer {
            containerController.addClosedHandler { [self] abortReason in
                guard !didSettle, let abortReason else { return }
                abort(reason: abortReason)
            }
        }
        let operationController = operationController
        settlementTask = Task { @MainActor [weak self, weak containerController] in
            _ = await operationController.whenSettled()
            guard let self, !Task.isCancelled else { return }
            self.didSettle = true
            let onSettled = self.onSettledHandler
            self.onSettledHandler = nil
            onSettled?()
            guard usesAppContainer, let containerController, !containerController.isClosed else { return }
            containerController.requestDismissWithoutAbort()
        }
    }

    internal func abort(reason: Reason) {
        guard !didAbort, !didSettle else { return }
        didAbort = true
        operationController.abort(reason: reason)
    }
}
