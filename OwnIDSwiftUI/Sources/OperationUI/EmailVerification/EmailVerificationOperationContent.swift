@_spi(OwnIDInternal) import OwnIDCore
import SwiftUI

internal struct EmailVerificationOperationRenderContext {
    internal let controller: any EmailVerificationOperationController
    internal let uiProvider: (any EmailVerificationUIProvider)?
    internal let stringsProvider: any EmailVerificationStringsProvider

    @MainActor
    internal static func resolve(
        operationController: any OperationController,
        instanceResolver: any DIContainerResolver,
        overrides: OwnIDOperationOverrides,
        abortOperation: @MainActor (Reason) -> Void
    ) -> Self? {
        guard let emailController = operationController as? any EmailVerificationOperationController else { return nil }
        let operationType = operationController.operationID.type
        let logger = instanceResolver.getOrNil(type: OwnIDLogRouter.self)

        let uiProvider = instanceResolver.getOrNil(type: (any EmailVerificationUIProvider).self)
        guard let stringsProvider = instanceResolver.getOrNil(type: (any EmailVerificationStringsProvider).self) else {
            abortOperation(.systemError(details: "Missing strings provider for \(operationType)"))
            return nil
        }
        guard uiProvider != nil || overrides.emailVerificationContent != nil else {
            logger?.logW(source: Self.self, prefix: "resolve", message: "Missing UI renderer/provider for \(operationType)")
            abortOperation(.systemError(details: "Missing UI provider for \(operationType)"))
            return nil
        }

        return Self(controller: emailController, uiProvider: uiProvider, stringsProvider: stringsProvider)
    }
}

@MainActor
internal struct EmailVerificationOperationContentView: View {
    private let controller: any EmailVerificationOperationController
    private let uiProvider: (any EmailVerificationUIProvider)?
    internal let isReadyForInitialFocus: Bool
    internal let errorTextProvider: ((ErrorCode) -> String)?
    internal let onMissingRenderer: @MainActor () -> Void

    @State private var model: VerificationOperationContentModel<EmailVerificationOperationState, EmailVerificationStrings>

    internal init(
        controller: any EmailVerificationOperationController,
        uiProvider: (any EmailVerificationUIProvider)?,
        stringsProvider: any EmailVerificationStringsProvider,
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
            initialValue: VerificationOperationContentModel(
                initialState: .created,
                stateStream: controller.stateStream(),
                stringsStream: stringsProvider.getStrings(params: EmailVerificationStringsParams()),
                shouldFinishStateObservation: { state in
                    if case .completed = state { return true }
                    return false
                }
            )
        )
    }

    internal var body: some View {
        EmailVerificationOperationObservedContentView(
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
private struct EmailVerificationOperationObservedContentView: View {
    @ObservedObject internal var model: VerificationOperationContentModel<EmailVerificationOperationState, EmailVerificationStrings>

    internal let controller: any EmailVerificationOperationController
    internal let uiProvider: (any EmailVerificationUIProvider)?
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
        case (.active(let uiState, _), let strings?):
            if let builder = overrides.emailVerificationContent {
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
