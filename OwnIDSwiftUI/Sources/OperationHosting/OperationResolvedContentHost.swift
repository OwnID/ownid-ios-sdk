@_spi(OwnIDInternal) import OwnIDCore
import SwiftUI

internal struct OperationResolvedContentHost: View {
    private enum ResolveState {
        case loading
        case resolved(ResolvedContent)
        case missing
    }

    private enum ResolvedContent {
        case loginID(LoginIDCollectOperationRenderContext)
        case email(EmailVerificationOperationRenderContext)
        case phone(PhoneVerificationOperationRenderContext)

        @MainActor
        fileprivate static func resolve(
            operationController: any OperationController,
            instanceResolver: any DIContainerResolver,
            overrides: OwnIDOperationOverrides,
            abortOperation: @escaping @MainActor (Reason) -> Void
        ) -> Self? {
            let logger = instanceResolver.getOrNil(type: OwnIDLogRouter.self)

            switch operationController.operationID.type {
            case .loginIDCollect:
                return LoginIDCollectOperationRenderContext.resolve(
                    operationController: operationController,
                    instanceResolver: instanceResolver,
                    overrides: overrides,
                    abortOperation: abortOperation
                ).map(Self.loginID)
            case .emailVerification:
                return EmailVerificationOperationRenderContext.resolve(
                    operationController: operationController,
                    instanceResolver: instanceResolver,
                    overrides: overrides,
                    abortOperation: abortOperation
                ).map(Self.email)
            case .phoneNumberVerification:
                return PhoneVerificationOperationRenderContext.resolve(
                    operationController: operationController,
                    instanceResolver: instanceResolver,
                    overrides: overrides,
                    abortOperation: abortOperation
                ).map(Self.phone)
            default:
                let message = "Unsupported operation type in host container: \(operationController.operationID.type)"
                logger?.logW(
                    source: Self.self,
                    prefix: "resolve",
                    message: message
                )
                abortOperation(.systemError(details: message))
                return nil
            }
        }

        @MainActor
        @ViewBuilder
        fileprivate func makeView(
            isReadyForInitialFocus: Bool,
            errorTextProvider: ((ErrorCode) -> String)?,
            onMissingRenderer: @escaping @MainActor () -> Void
        ) -> some View {
            switch self {
            case .loginID(let context):
                LoginIDCollectOperationContentView(
                    controller: context.controller,
                    uiProvider: context.uiProvider,
                    stringsProvider: context.stringsProvider,
                    isReadyForInitialFocus: isReadyForInitialFocus,
                    errorTextProvider: errorTextProvider,
                    onMissingRenderer: onMissingRenderer
                )
            case .email(let context):
                EmailVerificationOperationContentView(
                    controller: context.controller,
                    uiProvider: context.uiProvider,
                    stringsProvider: context.stringsProvider,
                    isReadyForInitialFocus: isReadyForInitialFocus,
                    errorTextProvider: errorTextProvider,
                    onMissingRenderer: onMissingRenderer
                )
            case .phone(let context):
                PhoneVerificationOperationContentView(
                    controller: context.controller,
                    uiProvider: context.uiProvider,
                    stringsProvider: context.stringsProvider,
                    isReadyForInitialFocus: isReadyForInitialFocus,
                    errorTextProvider: errorTextProvider,
                    onMissingRenderer: onMissingRenderer
                )
            }
        }
    }

    private let instanceResolver: any DIContainerResolver
    private let operationController: any OperationController
    private let errorTextProvider: ((ErrorCode) -> String)?
    private let isReadyForInitialFocus: Bool
    private let abortOperation: @MainActor (Reason) -> Void
    private let onMissingRenderer: @MainActor () -> Void

    @Environment(\.ownIDOperationOverrides) private var overrides
    @State private var resolveState: ResolveState = .loading

    internal init(
        instanceResolver: any DIContainerResolver,
        operationController: any OperationController,
        errorTextProvider: ((ErrorCode) -> String)?,
        isReadyForInitialFocus: Bool,
        abortOperation: @escaping @MainActor (Reason) -> Void,
        onMissingRenderer: @escaping @MainActor () -> Void
    ) {
        self.instanceResolver = instanceResolver
        self.operationController = operationController
        self.errorTextProvider = errorTextProvider
        self.isReadyForInitialFocus = isReadyForInitialFocus
        self.abortOperation = abortOperation
        self.onMissingRenderer = onMissingRenderer
    }

    internal var body: some View {
        ZStack {
            switch resolveState {
            case .loading:
                OwnIDLoadingPlaceholderView()
            case .resolved(let content):
                content.makeView(
                    isReadyForInitialFocus: isReadyForInitialFocus,
                    errorTextProvider: errorTextProvider,
                    onMissingRenderer: {
                        setResolveState(.missing)
                        onMissingRenderer()
                    }
                )
            case .missing:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity)
        .taskCompat(id: operationController.operationID) {
            setResolveState(.loading)
            let content = ResolvedContent.resolve(
                operationController: operationController,
                instanceResolver: instanceResolver,
                overrides: overrides,
                abortOperation: abortOperation
            )
            setResolveState(content.map(ResolveState.resolved) ?? .missing)
        }
    }

    @MainActor
    private func setResolveState(_ state: ResolveState) {
        resolveState = state
    }
}
