@_spi(OwnIDInternal) import OwnIDCore
import SwiftUI

/// Internal lifecycle bridge between SwiftUI presentation and one operation controller.
///
/// The host resolves the current instance container, renders operation content, and keeps abort/settlement ownership
/// on the operation controller. Embedded operation views abort when they disappear; container-backed presentation waits
/// for the container controller to report final close so dismissal can drive cancellation. Rendering and content
/// callbacks stay in the resolved content host; this boundary only coordinates instance availability, cancellation,
/// settlement, and close signals.
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
        self._instanceResolver = State(initialValue: OwnID.getInstanceContainer(instanceName))
        self._lifecycleSession = State(
            initialValue: OperationLifecycleSession(operationController: operationController, usesAppContainer: containerController != nil)
        )
    }

    internal init(
        instanceResolver: any DIContainerResolver,
        operationController: Controller,
        renderController: any OperationController,
        containerController: OwnIDUIContainerController,
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
            initialValue: OperationLifecycleSession(operationController: operationController, usesAppContainer: true)
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
                    isReadyForInitialFocus: usesAppContainer ? containerController.isOpened : true,
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
        instanceResolver = nil

        for await instanceContainer in OwnID.getInstanceContainerStream(instanceName) {
            if Task.isCancelled { break }

            guard let instanceContainer else {
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

            instanceResolver = instanceContainer
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
/// The session keeps cancellation idempotent and separates two presentation modes:
/// embedded views cancel on disappearance, while app-owned containers decide cancellation when they report final close.
@MainActor
internal final class OperationLifecycleSession<Controller: OperationController> {
    private let operationController: Controller
    private let usesAppContainer: Bool
    private var didAbort = false
    private var didRegisterClosedHandler = false
    private var didSettle = false
    private var didStartSettlementTask = false
    private var settlementTask: Task<Void, Never>?

    internal init(operationController: Controller, usesAppContainer: Bool) {
        self.operationController = operationController
        self.usesAppContainer = usesAppContainer
    }

    deinit {
        settlementTask?.cancel()
    }

    internal func activate(containerController: OwnIDUIContainerController, onSettled: @escaping @MainActor () -> Void) {
        if usesAppContainer, !didRegisterClosedHandler {
            didRegisterClosedHandler = true
            containerController.addClosedHandler { [self] abortReason in
                guard !didSettle, let abortReason else { return }
                abort(reason: abortReason)
            }
        }
        startSettlementTaskIfNeeded(containerController: containerController, onSettled: onSettled)
    }

    internal func abort(reason: Reason) {
        guard !didAbort, !didSettle else { return }
        didAbort = true
        if !usesAppContainer {
            settlementTask?.cancel()
        }
        operationController.abort(reason: reason)
    }

    private func startSettlementTaskIfNeeded(containerController: OwnIDUIContainerController, onSettled: @escaping @MainActor () -> Void) {
        guard !didStartSettlementTask else { return }
        didStartSettlementTask = true
        let operationController = operationController

        settlementTask = Task { @MainActor [weak self, weak containerController] in
            _ = await operationController.whenSettled()
            guard let self, !Task.isCancelled else { return }
            self.didSettle = true
            onSettled()
            guard usesAppContainer, let containerController, !containerController.isClosed else { return }
            containerController.requestDismissWithoutAbort()
        }
    }
}
