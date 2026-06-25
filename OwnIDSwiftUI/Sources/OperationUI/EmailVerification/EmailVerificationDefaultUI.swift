import OwnIDCore
import SwiftUI

internal struct EmailVerificationUIDefaultProvider: EmailVerificationUIProvider, Sendable {
    @MainActor
    internal func content(
        uiState: EmailVerificationUIState,
        uiStrings: EmailVerificationStrings,
        errorTextProvider: ((ErrorCode) -> String)?,
        isReadyForInitialFocus: Bool
    ) -> AnyView {
        AnyView(
            EmailVerificationDefaultView(
                uiState: uiState,
                uiStrings: uiStrings,
                errorTextProvider: errorTextProvider,
                isReadyForInitialFocus: isReadyForInitialFocus
            )
        )
    }
}

internal struct EmailVerificationDefaultView: View {
    private let uiState: EmailVerificationUIState
    private let uiStrings: EmailVerificationStrings
    private let errorTextProvider: ((ErrorCode) -> String)?
    private let isReadyForInitialFocus: Bool
    private let errorClearDelayNs: UInt64

    internal init(
        uiState: EmailVerificationUIState,
        uiStrings: EmailVerificationStrings,
        errorTextProvider: ((ErrorCode) -> String)? = nil,
        isReadyForInitialFocus: Bool = true,
        errorClearDelayNs: UInt64 = 3_000_000_000
    ) {
        self.uiState = uiState
        self.uiStrings = uiStrings
        self.errorTextProvider = errorTextProvider
        self.isReadyForInitialFocus = isReadyForInitialFocus
        self.errorClearDelayNs = errorClearDelayNs
    }

    internal var body: some View {
        VerificationDefaultView(
            title: uiStrings.title,
            message: uiStrings.message,
            description: uiStrings.description,
            resend: uiStrings.resend,
            cancel: uiStrings.cancel,
            notYou: uiStrings.notYou,
            challenge: uiState.challenge,
            isBusy: uiState.isBusy,
            error: uiState.error,
            errorTextProvider: errorTextProvider,
            isReadyForInitialFocus: isReadyForInitialFocus,
            errorClearDelayNs: errorClearDelayNs,
            onCodeEntered: uiState.onCodeEntered,
            onCancel: uiState.onCancel,
            onNotYou: uiState.onNotYou,
            onResend: uiState.onResend
        )
    }
}
