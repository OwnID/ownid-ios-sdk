@_spi(OwnIDInternal) import OwnIDCore
import SwiftUI

internal struct LoginIDCollectOperationRenderContext {
    internal let controller: any LoginIDCollectOperationController
    internal let uiProvider: (any LoginIDCollectUIProvider)?
    internal let stringsProvider: any LoginIDCollectStringsProvider

    @MainActor
    internal static func resolve(
        operationController: any OperationController,
        instanceResolver: any DIContainerResolver,
        overrides: OwnIDOperationOverrides,
        abortOperation: @MainActor (Reason) -> Void
    ) -> Self? {
        guard let loginIDController = operationController as? any LoginIDCollectOperationController else { return nil }
        let operationType = operationController.operationID.type
        let logger = instanceResolver.getOrNil(type: OwnIDLogRouter.self)

        let uiProvider = instanceResolver.getOrNil(type: (any LoginIDCollectUIProvider).self)
        guard let stringsProvider = instanceResolver.getOrNil(type: (any LoginIDCollectStringsProvider).self) else {
            abortOperation(.systemError(details: "Missing strings provider for \(operationType)"))
            return nil
        }
        guard uiProvider != nil || overrides.loginIDCollectContent != nil else {
            logger?.logW(source: Self.self, prefix: "resolve", message: "Missing UI renderer/provider for \(operationType)")
            abortOperation(.systemError(details: "Missing UI provider for \(operationType)"))
            return nil
        }

        return Self(controller: loginIDController, uiProvider: uiProvider, stringsProvider: stringsProvider)
    }
}

@MainActor
internal struct LoginIDCollectOperationContentView: View {
    private let controller: any LoginIDCollectOperationController
    private let uiProvider: (any LoginIDCollectUIProvider)?
    internal let isReadyForInitialFocus: Bool
    internal let errorTextProvider: ((ErrorCode) -> String)?
    internal let onMissingRenderer: @MainActor () -> Void

    @State private var model: LoginIDCollectContentModel

    internal init(
        controller: any LoginIDCollectOperationController,
        uiProvider: (any LoginIDCollectUIProvider)?,
        stringsProvider: any LoginIDCollectStringsProvider,
        isReadyForInitialFocus: Bool,
        errorTextProvider: ((ErrorCode) -> String)?,
        onMissingRenderer: @escaping @MainActor () -> Void
    ) {
        self.controller = controller
        self.uiProvider = uiProvider
        self.isReadyForInitialFocus = isReadyForInitialFocus
        self.errorTextProvider = errorTextProvider
        self.onMissingRenderer = onMissingRenderer
        self._model = State(
            initialValue: LoginIDCollectContentModel(
                controller: controller,
                stringsProvider: stringsProvider
            )
        )
    }

    internal var body: some View {
        LoginIDCollectOperationObservedContentView(
            model: model,
            controller: controller,
            uiProvider: uiProvider,
            isReadyForInitialFocus: isReadyForInitialFocus,
            errorTextProvider: errorTextProvider,
            onMissingRenderer: onMissingRenderer
        )
    }
}

@MainActor
private struct LoginIDCollectOperationObservedContentView: View {
    @ObservedObject internal var model: LoginIDCollectContentModel

    internal let controller: any LoginIDCollectOperationController
    internal let uiProvider: (any LoginIDCollectUIProvider)?
    internal let isReadyForInitialFocus: Bool
    internal let errorTextProvider: ((ErrorCode) -> String)?
    internal let onMissingRenderer: @MainActor () -> Void

    @Environment(\.ownIDOperationOverrides) private var overrides

    internal var body: some View {
        content
            .onAppear {
                model.startObserving()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch (model.operationState, model.resolvedStrings) {
        case (.active(let uiState), let strings?):
            if let builder = overrides.loginIDCollectContent {
                builder(uiState, strings, errorTextProvider, isReadyForInitialFocus)
            } else if let uiProvider {
                uiProvider.content(
                    uiState: uiState,
                    uiStrings: strings,
                    errorTextProvider: errorTextProvider,
                    isReadyForInitialFocus: isReadyForInitialFocus
                )
            } else {
                OwnIDLoadingPlaceholderView()
                    .taskCompat(id: controller.operationID) {
                        onMissingRenderer()
                    }
            }
        default:
            OwnIDLoadingPlaceholderView()
        }
    }
}

@MainActor
private final class LoginIDCollectContentModel: ObservableObject {
    @Published internal var operationState: LoginIDCollectOperationState = .created
    @Published internal var resolvedStrings: LoginIDCollectStrings?

    private let controller: any LoginIDCollectOperationController
    private let stringsProvider: any LoginIDCollectStringsProvider
    private var stateTask: Task<Void, Never>?
    private var stringsTask: Task<Void, Never>?
    private var activeLoginIDTypes: [LoginIDType]?

    fileprivate init(
        controller: any LoginIDCollectOperationController,
        stringsProvider: any LoginIDCollectStringsProvider
    ) {
        self.controller = controller
        self.stringsProvider = stringsProvider
    }

    deinit {
        stateTask?.cancel()
        stringsTask?.cancel()
    }

    fileprivate func startObserving() {
        guard stateTask == nil else { return }
        startStateObservation()
    }

    private func startStateObservation() {
        stateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await state in controller.stateStream() {
                if Task.isCancelled { break }
                operationState = state
                updateStringsObservation(for: state.activeLoginIDTypes)
                if case .completed = state { break }
            }
        }
    }

    private func updateStringsObservation(for loginIDTypes: [LoginIDType]?) {
        guard activeLoginIDTypes != loginIDTypes else { return }
        activeLoginIDTypes = loginIDTypes
        stringsTask?.cancel()
        stringsTask = nil

        guard let loginIDTypes else {
            resolvedStrings = nil
            return
        }

        stringsTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await newStrings
                in stringsProvider
                .getStrings(params: LoginIDCollectStringsParams(loginIDTypes: loginIDTypes))
                .compactMap({ $0 })
            {
                if Task.isCancelled { break }
                resolvedStrings = newStrings
            }
        }
    }
}

extension LoginIDCollectOperationState {
    fileprivate var activeLoginIDTypes: [LoginIDType]? {
        if case .active(let uiState) = self { return uiState.collectableLoginIDTypes }
        return nil
    }
}
