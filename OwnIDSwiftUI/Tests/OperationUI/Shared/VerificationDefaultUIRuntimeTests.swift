import SwiftUI
import Testing
import UIKit

@_spi(OwnIDInternal) @testable import OwnIDCore
@_spi(OwnIDInternal) @testable import OwnIDSwiftUI

@MainActor
@Suite(.serialized)
struct VerificationDefaultUIRuntimeTests {

    @Test func `OTP detail text substitutes code length and channel placeholders`() {
        let emailHost = SwiftUIRuntimeHost(
            rootView: verificationView(
                message: "Enter the %CODE_LENGTH%-digit code sent to %LOGIN_ID%.",
                challenge: verificationChallenge(length: 6, channel: OperationChannel(channel: "u***@example.test", id: "email-main"))
            )
        )
        defer { emailHost.close() }

        let channeledHost = SwiftUIRuntimeHost(
            rootView: verificationView(
                message: "Enter the %CODE_LENGTH%-digit code sent to %LOGIN_ID%.",
                challenge: verificationChallenge(length: 8, channel: OperationChannel(channel: "+1******0100", id: "phone-main"))
            )
        )
        defer { channeledHost.close() }

        let emailLabels = emailHost.accessibilityLabels()
        let phoneLabels = channeledHost.accessibilityLabels()
        #expect(emailLabels.contains("Enter the 6-digit code sent to u***@example.test."))
        #expect(!emailLabels.contains("email-main"))
        #expect(phoneLabels.contains("Enter the 8-digit code sent to +1******0100."))
        #expect(!phoneLabels.contains("phone-main"))
    }

    @Test func `OTP bridge exposes accessible one-time-code text input and hides decorative slots`() async throws {
        let host = SwiftUIRuntimeHost(
            rootView: verificationView(description: "Verification code")
        )
        defer { host.close() }
        await host.settle()

        let textField = try #require(host.textFields().first)
        let accessibilityLabels = host.accessibilityLabels()

        #expect(textField.keyboardType == .numberPad)
        #expect(textField.textContentType == .oneTimeCode)
        #expect(textField.isAccessibilityElement)
        #expect(textField.accessibilityElementsHidden == false)
        #expect(accessibilityLabels.contains("Verification code"))

        await enterText("123", in: textField, host: host)
        let exposedDigitLabels = host.accessibilityElements()
            .compactMap(\.accessibilityLabel)
            .filter { ["1", "2", "3"].contains($0) }
        #expect(exposedDigitLabels.isEmpty)
    }

    @Test func `OTP bridge normalizes input and submits when expected length is reached`() async throws {
        let recorder = SubmittedCodeRecorder()
        let host = SwiftUIRuntimeHost(
            rootView: verificationView(onCodeEntered: recorder.record)
        )
        defer { host.close() }
        await host.settle()

        let textField = try #require(host.textFields().first)

        await enterText("12x٣", in: textField, host: host)
        #expect(textField.text == "123")
        #expect(recorder.codes == [])

        await enterText("a1 ٢٣۴۵٦7", in: textField, host: host)
        #expect(textField.text == "123456")
        #expect(recorder.codes == ["123456"])
    }

    @Test func `OTP error clears partial input refocuses entry and allows reentry`() async throws {
        let recorder = SubmittedCodeRecorder()
        let challenge = verificationChallenge()
        let host = SwiftUIRuntimeHost(
            rootView: verificationView(
                challenge: challenge,
                isReadyForInitialFocus: false,
                onCodeEntered: recorder.record
            )
        )
        defer { host.close() }
        await host.settle()

        let initialTextField = try #require(host.textFields().first)
        await enterText("123", in: initialTextField, host: host)
        #expect(initialTextField.text == "123")

        host.update(
            rootView: verificationView(
                challenge: challenge,
                error: UIError(errorCode: .verificationCodeWrong, localizedMessage: "Invalid code"),
                isReadyForInitialFocus: false,
                onCodeEntered: recorder.record
            )
        )
        await host.settle()

        let clearedTextField = try #require(host.textFields().first)
        #expect(clearedTextField.text == "")
        if !UIAccessibility.isVoiceOverRunning {
            #expect(clearedTextField.isFirstResponder)
        }

        await enterText("654321", in: clearedTextField, host: host)
        #expect(recorder.codes == ["654321"])
    }

    @Test func `OTP resend waits for policy visibility and invokes resend callback`() async throws {
        let recorder = VerificationActionRecorder()
        let host = SwiftUIRuntimeHost(
            rootView: verificationView(
                challenge: verificationChallenge(debounce: 0),
                onResend: recorder.recordResend
            )
        )
        defer { host.close() }
        await host.settle(cycles: 4)

        try activateControl(labeled: "Resend", in: host)
        await host.settle(cycles: 4)

        #expect(recorder.resendCount == 1)
        #expect(host.accessibilityLabels().contains("Resend"))
    }

    @Test func `OTP busy state blocks code submission not-you action and direct input edits`() async throws {
        let codeRecorder = SubmittedCodeRecorder()
        let actionRecorder = VerificationActionRecorder()
        let host = SwiftUIRuntimeHost(
            rootView: verificationView(
                isBusy: true,
                onCodeEntered: codeRecorder.record,
                onNotYou: actionRecorder.recordNotYou
            )
        )
        defer { host.close() }
        await host.settle()

        let textField = try #require(host.textFields().first)
        let delegate = try #require(textField.delegate)

        let acceptsInput = delegate.textField?(
            textField,
            shouldChangeCharactersIn: NSRange(location: 0, length: 0),
            replacementString: "123456"
        )
        await enterText("123456", in: textField, host: host)
        let didActivateNotYou = try attemptActivateControl(labeled: "Not you", in: host)
        await host.settle()

        #expect(acceptsInput == false)
        #expect(didActivateNotYou == false)
        #expect(codeRecorder.codes.isEmpty)
        #expect(actionRecorder.notYouCount == 0)
    }

    @Test func `OTP busy state exposes deterministic accessibility control traits`() async throws {
        let host = SwiftUIRuntimeHost(
            rootView: verificationView(isBusy: true)
        )
        defer { host.close() }
        await host.settle()

        let cancel = try #require(
            host.accessibilityElements().first { $0.accessibilityLabel == "Cancel" },
            "Expected mounted cancel control accessibility element"
        )
        let notYou = try #require(
            host.accessibilityElements().first { $0.accessibilityLabel == "Not you" },
            "Expected mounted not-you control accessibility element"
        )

        #expect(cancel.accessibilityTraits.contains(.button))
        #expect(cancel.accessibilityTraits.contains(.notEnabled) == false)
        #expect(notYou.accessibilityTraits.contains(.button))
        #expect(notYou.accessibilityTraits.contains(.notEnabled))
    }

    @Test func `Reduce Motion disables shake animatable data`() {
        #expect(resolvedShakeAnimatableData(4, isEnabled: true) == 4)
        #expect(resolvedShakeAnimatableData(4, isEnabled: false) == 0)
    }

    @available(iOS 15.0, *)
    @Test func `Email OTP layout reports bounded fitting size under constrained width and large Dynamic Type`() async throws {
        let host = SwiftUIRuntimeHost(
            rootView: emailVerificationView()
                .environment(\.dynamicTypeSize, .accessibility3),
            size: CGSize(width: 220, height: 520)
        )
        defer { host.close() }
        await host.settle(cycles: 4)

        host.assertFittingSize(.constrainedOperationUI)
        let textField = try #require(host.textFields().first)

        host.assertLaidOut(textField, maxWidth: 220)
        #expect(textField.textContentType == .oneTimeCode)
    }

    @available(iOS 15.0, *)
    @Test func `Phone OTP layout reports bounded fitting size under constrained width and large Dynamic Type`() async throws {
        let host = SwiftUIRuntimeHost(
            rootView: phoneVerificationView()
                .environment(\.dynamicTypeSize, .accessibility3),
            size: CGSize(width: 220, height: 520)
        )
        defer { host.close() }
        await host.settle(cycles: 4)

        host.assertFittingSize(.constrainedOperationUI)
        let textField = try #require(host.textFields().first)

        host.assertLaidOut(textField, maxWidth: 220)
        #expect(textField.textContentType == .oneTimeCode)
    }
}

@MainActor
private func verificationView(
    title: String = "Confirm code",
    message: String = "Enter the %CODE_LENGTH%-digit code sent to %LOGIN_ID%.",
    description: String = "Verification code",
    challenge: VerificationChallenge = verificationChallenge(),
    isBusy: Bool = false,
    error: UIError? = nil,
    isReadyForInitialFocus: Bool = true,
    onCodeEntered: @escaping (String) -> Void = { _ in },
    onNotYou: @escaping () -> Void = {},
    onResend: @escaping () -> Void = {}
) -> VerificationDefaultView {
    VerificationDefaultView(
        title: title,
        message: message,
        description: description,
        resend: "Resend",
        cancel: "Cancel",
        notYou: "Not you",
        challenge: challenge,
        isBusy: isBusy,
        error: error,
        errorTextProvider: nil,
        isReadyForInitialFocus: isReadyForInitialFocus,
        errorClearDelayNs: 60_000_000_000,
        onCodeEntered: onCodeEntered,
        onCancel: {},
        onNotYou: onNotYou,
        onResend: onResend
    )
}

@MainActor
private func emailVerificationView() -> EmailVerificationDefaultView {
    EmailVerificationDefaultView(
        uiState: EmailVerificationUIState(
            challenge: verificationChallenge(
                channel: OperationChannel(channel: "long.email.alias@example.test", id: "email-layout")
            ),
            onCodeEntered: { _ in },
            onCancel: {},
            onNotYou: {},
            onResend: {}
        ),
        uiStrings: EmailVerificationStrings(
            title: "Verify your email address",
            message: "Enter the %CODE_LENGTH%-digit code sent to %LOGIN_ID% to continue securely.",
            description: "Verification code",
            resend: "Resend email",
            cancel: "Cancel",
            notYou: "Not you?"
        ),
        isReadyForInitialFocus: false
    )
}

@MainActor
private func phoneVerificationView() -> PhoneVerificationDefaultView {
    PhoneVerificationDefaultView(
        uiState: PhoneVerificationUIState(
            challenge: verificationChallenge(
                channel: OperationChannel(channel: "+1 555 010 1234", id: "phone-layout")
            ),
            onCodeEntered: { _ in },
            onCancel: {},
            onNotYou: {},
            onResend: {}
        ),
        uiStrings: PhoneVerificationStrings(
            title: "Verify your phone number",
            message: "Enter the %CODE_LENGTH%-digit code sent to %LOGIN_ID% to continue securely.",
            description: "Verification code",
            resend: "Resend SMS",
            cancel: "Cancel",
            notYou: "Not you?"
        ),
        isReadyForInitialFocus: false
    )
}

private func verificationChallenge(
    id: String = "verification-challenge",
    length: Int = 6,
    channel: OperationChannel = OperationChannel(channel: "user@example.test", id: "email-main"),
    debounce: Int = 1
) -> VerificationChallenge {
    VerificationChallenge(
        challengeID: ChallengeID(id),
        resendPolicy: .init(allow: true, attempts: 3, debounce: debounce),
        timeout: Timeout(milliseconds: 10_000),
        attempts: 3,
        methods: .init(otp: .init(length: length), magicLink: nil),
        channel: channel
    )
}

@MainActor
private final class SubmittedCodeRecorder {
    private(set) var codes: [String] = []

    func record(_ code: String) {
        codes.append(code)
    }
}

@MainActor
private final class VerificationActionRecorder {
    private(set) var resendCount = 0
    private(set) var notYouCount = 0

    func recordResend() {
        resendCount += 1
    }

    func recordNotYou() {
        notYouCount += 1
    }
}
