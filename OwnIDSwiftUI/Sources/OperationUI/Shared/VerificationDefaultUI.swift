import OwnIDCore
import SwiftUI
import UIKit

internal struct VerificationDefaultView: View {
    @Environment(\.ownIDTheme) private var ownIDTheme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    private let title: String
    private let message: String
    private let description: String
    private let resend: String
    private let cancel: String
    private let notYou: String
    private let challenge: VerificationChallenge
    private let isBusy: Bool
    private let error: UIError?
    private let errorTextProvider: ((ErrorCode) -> String)?
    private let isReadyForInitialFocus: Bool
    private let errorClearDelayNs: UInt64
    private let onCodeEntered: (String) -> Void
    private let onCancel: () -> Void
    private let onNotYou: () -> Void
    private let onResend: () -> Void

    @State private var otpCode = ""
    @State private var isResendVisible = false
    @State private var resendCount = 0
    @State private var isErrorUIVisible = false
    @State private var shakeAnimationTrigger = 0
    @State private var otpFocusRequestTrigger = 0
    @State private var showErrorText = false
    @State private var errorFocusTrigger = 0
    @State private var otpSubmitThrottler = UserActionThrottler()

    private var resendDebounceNs: UInt64 { UInt64(challenge.resendPolicy.debounce) * 1_000_000_000 }

    private var resendTaskKey: String {
        "\(challenge.challengeID)|\(challenge.resendPolicy.debounce)|\(resendCount)"
    }

    private var isResendAllowedNow: Bool {
        challenge.resendPolicy.allow && error?.errorCode != .maximumResendAttemptsReached
    }

    internal init(
        title: String,
        message: String,
        description: String,
        resend: String,
        cancel: String,
        notYou: String,
        challenge: VerificationChallenge,
        isBusy: Bool,
        error: UIError?,
        errorTextProvider: ((ErrorCode) -> String)?,
        isReadyForInitialFocus: Bool,
        errorClearDelayNs: UInt64 = 3_000_000_000,
        onCodeEntered: @escaping (String) -> Void,
        onCancel: @escaping () -> Void,
        onNotYou: @escaping () -> Void,
        onResend: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.description = description
        self.resend = resend
        self.cancel = cancel
        self.notYou = notYou
        self.challenge = challenge
        self.isBusy = isBusy
        self.error = error
        self.errorTextProvider = errorTextProvider
        self.isReadyForInitialFocus = isReadyForInitialFocus
        self.errorClearDelayNs = errorClearDelayNs
        self.onCodeEntered = onCodeEntered
        self.onCancel = onCancel
        self.onNotYou = onNotYou
        self.onResend = onResend
    }

    private var colors: OwnIDColors {
        (ownIDTheme ?? OwnIDTheme.capture(colorScheme: colorScheme)).colors
    }

    internal var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(.headline, design: .default).weight(.bold))
                .foregroundColor(colors.onSurface)
                .multilineTextAlignment(.center)
                .padding(EdgeInsets(top: 24, leading: 52, bottom: 10, trailing: 52))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)

            VStack(spacing: 0) {
                Text(detailsText)
                    .font(.subheadline)
                    .foregroundColor(colors.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .allowsTightening(true)
                    .padding(.bottom, 12)
                    .fixedSize(horizontal: false, vertical: true)

                Text(description)
                    .font(.body)
                    .foregroundColor(colors.onSurface)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 8)
                    .fixedSize(horizontal: false, vertical: true)

                otpEntryField
                    .shake(animatableData: shakeAnimationTrigger, isEnabled: !accessibilityReduceMotion)
                    .padding(.bottom, 4)

                ZStack {
                    if isBusy {
                        OwnIDSpinnerView()
                            .frame(width: 28, height: 28)
                            .padding(.top, 4)
                    } else if showErrorText, let error {
                        let message = errorText(for: error)
                        if #available(iOS 15.0, *) {
                            AccessibilityFocusedErrorText(
                                message: message,
                                color: colors.error,
                                alignment: .center,
                                focusTrigger: errorFocusTrigger
                            )
                        } else {
                            Text(message)
                                .font(.footnote)
                                .foregroundColor(colors.error)
                                .multilineTextAlignment(.center)
                        }
                    } else if isResendVisible && isResendAllowedNow {
                        OwnIDTextButtonView(text: resend, action: handleResendTapped)
                    }
                }
                .frame(minHeight: 44)

                HStack {
                    OwnIDTextButtonView(text: cancel, action: handleCancelTapped)
                    Spacer(minLength: 16)
                    OwnIDTextButtonView(text: notYou, isEnabled: !isBusy, action: handleNotYouTapped)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
        }
        .taskCompat(id: resendTaskKey) { await handleResendTask() }
        .taskCompat(id: shakeAnimationTrigger) { await handleErrorTask() }
        .onChangeCompat(of: error) { error in
            guard let error else { return }
            presentErrorState()
            requestErrorAccessibilityFocus(message: errorText(for: error))
        }
        .onChangeCompat(of: challenge.challengeID) { _ in
            resendCount = 0
            isResendVisible = false
        }
        .onChangeCompat(of: otpCode) { handleOTPInputChange($0) }
    }

    private var detailsText: String {
        message
            .replacingOccurrences(of: "%CODE_LENGTH%", with: String(codeLength))
            .replacingOccurrences(of: "%LOGIN_ID%", with: challenge.channel.channel)
    }

    private var codeLength: Int {
        challenge.methods.otp?.length ?? 4
    }

    private var otpEntryField: some View {
        OTPEntryField(
            code: $otpCode,
            codeLength: codeLength,
            isEditable: !isBusy,
            isErrorVisible: isErrorUIVisible,
            isReadyForInitialFocus: isReadyForInitialFocus,
            initialFocusResetID: challenge.challengeID.value,
            externalFocusRequestToken: otpFocusRequestTrigger,
            colors: colors,
            accessibilityLabel: description,
            accessibilityHint: otpAccessibilityHint
        )
    }

    private var otpAccessibilityHint: String {
        guard showErrorText, let error else { return detailsText }
        return "\(detailsText). \(errorText(for: error))"
    }

    private func errorText(for error: UIError) -> String {
        errorTextProvider?(error.errorCode) ?? error.localizedMessage
    }

    @MainActor
    private func handleResendTask() async {
        guard isResendAllowedNow else {
            isResendVisible = false
            return
        }
        isResendVisible = false
        guard (try? await Task.sleep(nanoseconds: resendDebounceNs)) != nil else { return }
        isResendVisible = true
    }

    @MainActor
    private func handleErrorTask() async {
        guard shakeAnimationTrigger > 0 else { return }
        guard (try? await Task.sleep(nanoseconds: errorClearDelayNs)) != nil else { return }
        isErrorUIVisible = false
    }

    @MainActor
    private func presentErrorState() {
        otpCode = ""
        isErrorUIVisible = true
        showErrorText = true
        shakeAnimationTrigger += 1
        if !shouldFocusErrorText {
            otpFocusRequestTrigger &+= 1
        }
    }

    @MainActor
    private func handleOTPInputChange(_ newCode: String) {
        if !newCode.isEmpty {
            isErrorUIVisible = false
            showErrorText = false
        }

        let truncatedCode = newCode.ownIDNormalizedASCIIDigits(maximumLength: codeLength)
        if truncatedCode != otpCode { otpCode = truncatedCode }
        if truncatedCode.count == codeLength, !isBusy {
            otpSubmitThrottler.processAction { onCodeEntered(truncatedCode) }
        }
    }

    @MainActor
    private func handleCancelTapped() {
        onCancel()
    }

    @MainActor
    private func handleNotYouTapped() {
        guard !isBusy else { return }
        onNotYou()
    }

    @MainActor
    private func handleResendTapped() {
        guard isResendVisible && isResendAllowedNow else { return }
        isResendVisible = false
        resendCount += 1
        onResend()
    }

    @MainActor
    private func requestErrorAccessibilityFocus(message: String) {
        if #available(iOS 15.0, *) {
            guard UIAccessibility.isVoiceOverRunning else { return }
            errorFocusTrigger &+= 1
        } else {
            UIAccessibility.post(notification: .announcement, argument: message)
        }
    }

    private var shouldFocusErrorText: Bool {
        if #available(iOS 15.0, *) {
            return UIAccessibility.isVoiceOverRunning
        }
        return false
    }
}
