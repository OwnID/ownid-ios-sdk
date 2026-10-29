import SwiftUI
import Testing
import UIKit

@_spi(OwnIDInternal) @testable import OwnIDCore
@_spi(OwnIDInternal) @testable import OwnIDSwiftUI

// Covers: UI-PRESENT-130, UI-PRESENT-260
@MainActor
@Suite(.serialized)
struct VerificationDefaultUIRuntimeTests {

    @Test func `Terminal verification stops strings observation without restarting or retaining the model`() async throws {
        let states = VerificationContentStream<Int>()
        let strings = VerificationContentStream<String?>()
        var model: VerificationOperationContentModel<Int, String>? = verificationContentModel(states: states, strings: strings)
        weak var weakModel = model
        var observationFinished = false
        let observation = Task { [model = model!] in
            defer { observationFinished = true }
            await model.observe()
        }
        defer { observation.cancel() }
        try await waitForVerificationObservation { states.subscriptionCount == 1 && strings.subscriptionCount == 1 }

        strings.yield("Initial strings")
        try await waitForVerificationObservation { model?.resolvedStrings == "Initial strings" }
        states.yield(2)
        try await waitForVerificationObservation { strings.cancellationCount == 1 }
        try await waitForVerificationObservation { observationFinished }
        await observation.value

        #expect(model?.operationState == 2)
        var terminalProbeFinished = false
        let terminalProbe = Task { [model = model!] in
            defer { terminalProbeFinished = true }
            await model.observe()
        }
        defer { terminalProbe.cancel() }
        try await waitForVerificationObservation { terminalProbeFinished }
        await terminalProbe.value
        #expect(states.subscriptionCount == 1)
        #expect(strings.subscriptionCount == 1)
        model = nil
        #expect(weakModel == nil)
    }

    @Test func `Canceled verification observation releases subscriptions and reappears with fresh streams and retained values`() async throws {
        let states = VerificationContentStream<Int>()
        let strings = VerificationContentStream<String?>()
        let model = verificationContentModel(states: states, strings: strings)
        #expect(states.subscriptionCount == 0)
        #expect(strings.subscriptionCount == 0)

        var firstObservationFinished = false
        let firstObservation = Task {
            defer { firstObservationFinished = true }
            await model.observe()
        }
        defer { firstObservation.cancel() }
        try await waitForVerificationObservation { states.subscriptionCount == 1 && strings.subscriptionCount == 1 }
        states.yield(1)
        strings.yield("First appearance")
        try await waitForVerificationObservation { model.operationState == 1 && model.resolvedStrings == "First appearance" }

        firstObservation.cancel()
        try await waitForVerificationObservation { firstObservationFinished }
        await firstObservation.value
        #expect(states.cancellationCount == 1)
        #expect(strings.cancellationCount == 1)

        var nextObservationFinished = false
        let nextObservation = Task {
            defer { nextObservationFinished = true }
            await model.observe()
        }
        defer { nextObservation.cancel() }
        try await waitForVerificationObservation { states.subscriptionCount == 2 && strings.subscriptionCount == 2 }
        #expect(model.operationState == 1)
        #expect(model.resolvedStrings == "First appearance")
        states.yield(2)
        strings.yield("Stale appearance")
        strings.yield(nil, subscription: 1)
        strings.yield("Second appearance", subscription: 1)
        states.yield(0, subscription: 1)
        try await waitForVerificationObservation { model.operationState == 0 && model.resolvedStrings == "Second appearance" }

        nextObservation.cancel()
        try await waitForVerificationObservation { nextObservationFinished }
        await nextObservation.value
        #expect(states.cancellationCount == 2)
        #expect(strings.cancellationCount == 2)
    }

    @Test func `Finished strings leave verification state active and state completion cancels remaining strings`() async throws {
        let states = VerificationContentStream<Int>()
        let strings = VerificationContentStream<String?>()
        let model = verificationContentModel(states: states, strings: strings)
        var firstObservationFinished = false
        let firstObservation = Task {
            defer { firstObservationFinished = true }
            await model.observe()
        }
        defer { firstObservation.cancel() }
        try await waitForVerificationObservation { states.subscriptionCount == 1 && strings.subscriptionCount == 1 }

        strings.yield("Embedded strings")
        strings.finish()
        try await waitForVerificationObservation { model.resolvedStrings == "Embedded strings" }
        states.yield(1)
        try await waitForVerificationObservation { model.operationState == 1 }
        states.finish()
        try await waitForVerificationObservation { firstObservationFinished }
        await firstObservation.value

        var nextObservationFinished = false
        let nextObservation = Task {
            defer { nextObservationFinished = true }
            await model.observe()
        }
        defer { nextObservation.cancel() }
        try await waitForVerificationObservation { states.subscriptionCount == 2 && strings.subscriptionCount == 2 }
        states.finish(subscription: 1)
        try await waitForVerificationObservation { strings.cancellationCount == 1 }
        try await waitForVerificationObservation { nextObservationFinished }
        await nextObservation.value
        #expect(model.operationState == 1)
        #expect(model.resolvedStrings == "Embedded strings")
    }

    @Test func `Email content observes busy and wrong-code states after loading and resubscribes after removal`() async throws {
        let controller = EmailVerificationOperationControllerImpl(
            operationID: OperationID(type: .emailVerification, id: "hosted-email-verification"),
            onUserAborted: { _ in }
        )
        let strings = VerificationContentStream<EmailVerificationStrings?>()
        let recorder = SubmittedCodeRecorder()
        let apiController = HostedEmailVerificationAPIController(challenge: verificationChallenge(length: 4))

        func showState(isBusy: Bool = false, error: UIError? = nil) {
            controller.state = .active(
                uiState: EmailVerificationUIState(
                    challenge: apiController.challenge,
                    isBusy: isBusy,
                    error: error,
                    onCodeEntered: { code in Task { @MainActor in recorder.record(code) } },
                    onCancel: {},
                    onNotYou: {},
                    onResend: {}
                ),
                apiController: apiController
            )
        }

        func makeContent() -> EmailVerificationOperationContentView {
            EmailVerificationOperationContentView(
                controller: controller,
                uiProvider: EmailVerificationUIDefaultProvider(),
                stringsProvider: HostedEmailVerificationStringsProvider(strings: strings),
                isReadyForInitialFocus: false,
                errorTextProvider: nil,
                onMissingRenderer: { Issue.record("Expected the default verification renderer") }
            )
        }

        let host = SwiftUIRuntimeHost(rootView: AnyView(makeContent()))
        defer { host.close() }
        try await waitForHostedVerification(host: host) { strings.subscriptionCount == 1 }
        #expect(host.textFields().isEmpty)

        strings.yield(.default)
        await host.settle(cycles: 20)
        #expect(host.textFields().isEmpty)
        showState()
        try await waitForHostedVerification(host: host) { !host.textFields().isEmpty }

        let textField = try #require(host.textFields().first)
        await enterText("1234", in: textField, host: host)
        try await waitForHostedVerification(host: host) { recorder.codes == ["1234"] }

        showState(isBusy: true)
        try await waitForHostedVerification(host: host) { acceptsVerificationInput(textField) == false }

        showState(error: UIError(errorCode: .verificationCodeWrong, localizedMessage: "Wrong code"))
        try await waitForHostedVerification(host: host) { host.textFields().first?.text == "" }
        let reentryField = try #require(host.textFields().first)
        #expect(acceptsVerificationInput(reentryField) == true)
        await enterText("5", in: reentryField, host: host)
        #expect(reentryField.text == "5")
        #expect(strings.subscriptionCount == 1)
        #expect(strings.cancellationCount == 0)

        host.update(rootView: AnyView(EmptyView()))
        try await waitForHostedVerification(host: host) { strings.cancellationCount == 1 }
        host.update(rootView: AnyView(makeContent()))
        try await waitForHostedVerification(host: host) { strings.subscriptionCount == 2 }
        strings.yield(.default, subscription: 1)
        try await waitForHostedVerification(host: host) { !host.textFields().isEmpty }
        let reappearedField = try #require(host.textFields().first)
        showState(isBusy: true)
        try await waitForHostedVerification(host: host) { acceptsVerificationInput(reappearedField) == false }
    }

    @Test func `Phone content observes busy and wrong-code states after loading and resubscribes after removal`() async throws {
        let controller = PhoneVerificationOperationControllerImpl(
            operationID: OperationID(type: .phoneNumberVerification, id: "hosted-phone-verification"),
            onUserAborted: { _ in }
        )
        let strings = VerificationContentStream<PhoneVerificationStrings?>()
        let recorder = SubmittedCodeRecorder()
        let apiController = HostedPhoneVerificationAPIController(challenge: verificationChallenge(length: 4))

        func showState(isBusy: Bool = false, error: UIError? = nil) {
            controller.state = .active(
                uiState: PhoneVerificationUIState(
                    challenge: apiController.challenge,
                    isBusy: isBusy,
                    error: error,
                    onCodeEntered: { code in Task { @MainActor in recorder.record(code) } },
                    onCancel: {},
                    onNotYou: {},
                    onResend: {}
                ),
                apiController: apiController
            )
        }

        func makeContent() -> PhoneVerificationOperationContentView {
            PhoneVerificationOperationContentView(
                controller: controller,
                uiProvider: PhoneVerificationUIDefaultProvider(),
                stringsProvider: HostedPhoneVerificationStringsProvider(strings: strings),
                isReadyForInitialFocus: false,
                errorTextProvider: nil,
                onMissingRenderer: { Issue.record("Expected the default verification renderer") }
            )
        }

        let host = SwiftUIRuntimeHost(rootView: AnyView(makeContent()))
        defer { host.close() }
        try await waitForHostedVerification(host: host) { strings.subscriptionCount == 1 }
        #expect(host.textFields().isEmpty)

        showState()
        await host.settle(cycles: 20)
        #expect(host.textFields().isEmpty)
        strings.yield(.default)
        try await waitForHostedVerification(host: host) { !host.textFields().isEmpty }

        let textField = try #require(host.textFields().first)
        await enterText("1234", in: textField, host: host)
        try await waitForHostedVerification(host: host) { recorder.codes == ["1234"] }

        showState(isBusy: true)
        try await waitForHostedVerification(host: host) { acceptsVerificationInput(textField) == false }

        showState(error: UIError(errorCode: .verificationCodeWrong, localizedMessage: "Wrong code"))
        try await waitForHostedVerification(host: host) { host.textFields().first?.text == "" }
        let reentryField = try #require(host.textFields().first)
        #expect(acceptsVerificationInput(reentryField) == true)
        await enterText("5", in: reentryField, host: host)
        #expect(reentryField.text == "5")
        #expect(strings.subscriptionCount == 1)
        #expect(strings.cancellationCount == 0)

        host.update(rootView: AnyView(EmptyView()))
        try await waitForHostedVerification(host: host) { strings.cancellationCount == 1 }
        host.update(rootView: AnyView(makeContent()))
        try await waitForHostedVerification(host: host) { strings.subscriptionCount == 2 }
        strings.yield(.default, subscription: 1)
        try await waitForHostedVerification(host: host) { !host.textFields().isEmpty }
        let reappearedField = try #require(host.textFields().first)
        showState(isBusy: true)
        try await waitForHostedVerification(host: host) { acceptsVerificationInput(reappearedField) == false }
    }

    @Test func `OTP bridge configures one-time-code text input traits`() async throws {
        let host = SwiftUIRuntimeHost(
            rootView: verificationView(description: "Verification code")
        )
        defer { host.close() }
        await host.settle()

        let textField = try #require(host.textFields().first)

        #expect(textField.keyboardType == .numberPad)
        #expect(textField.textContentType == .oneTimeCode)
        #expect(textField.isAccessibilityElement)
        #expect(textField.accessibilityElementsHidden == false)
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

    @Test func `Challenge identity resets email and phone OTP state`() async throws {
        do {
            let host = SwiftUIRuntimeHost(
                rootView: emailVerificationView(challenge: verificationChallenge(id: "email-challenge-1"))
            )
            defer { host.close() }
            await host.settle()

            let initialTextField = try #require(host.textFields().first)
            await enterText("12", in: initialTextField, host: host)
            #expect(initialTextField.text == "12")

            host.update(
                rootView: emailVerificationView(challenge: verificationChallenge(id: "email-challenge-2"))
            )
            await host.settle()

            let resetTextField = try #require(host.textFields().first)
            #expect(resetTextField.text == "")
        }

        do {
            let host = SwiftUIRuntimeHost(
                rootView: phoneVerificationView(challenge: verificationChallenge(id: "phone-challenge-1"))
            )
            defer { host.close() }
            await host.settle()

            let initialTextField = try #require(host.textFields().first)
            await enterText("34", in: initialTextField, host: host)
            #expect(initialTextField.text == "34")

            host.update(
                rootView: phoneVerificationView(challenge: verificationChallenge(id: "phone-challenge-2"))
            )
            await host.settle()

            let resetTextField = try #require(host.textFields().first)
            #expect(resetTextField.text == "")
        }
    }

    @Test func `OTP busy state blocks code submission and direct input edits`() async throws {
        let codeRecorder = SubmittedCodeRecorder()
        let host = SwiftUIRuntimeHost(
            rootView: verificationView(
                isBusy: true,
                onCodeEntered: codeRecorder.record
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

        #expect(acceptsInput == false)
        #expect(codeRecorder.codes.isEmpty)
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
private func emailVerificationView(
    challenge: VerificationChallenge = verificationChallenge(
        channel: OperationChannel(channel: "long.email.alias@example.test", id: "email-layout")
    )
) -> EmailVerificationDefaultView {
    EmailVerificationDefaultView(
        uiState: EmailVerificationUIState(
            challenge: challenge,
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
private func phoneVerificationView(
    challenge: VerificationChallenge = verificationChallenge(
        channel: OperationChannel(channel: "+1 555 010 1234", id: "phone-layout")
    )
) -> PhoneVerificationDefaultView {
    PhoneVerificationDefaultView(
        uiState: PhoneVerificationUIState(
            challenge: challenge,
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
private func verificationContentModel(
    states: VerificationContentStream<Int>,
    strings: VerificationContentStream<String?>
) -> VerificationOperationContentModel<Int, String> {
    VerificationOperationContentModel(
        initialState: 0,
        makeStateStream: { states.makeStream() },
        makeStringsStream: { strings.makeStream() },
        shouldFinishStateObservation: { $0 == 2 }
    )
}

@MainActor
private func waitForVerificationObservation(_ condition: @escaping @MainActor @Sendable () -> Bool) async throws {
    try await withSwiftUITestTimeout("verification observation", seconds: 2) { @MainActor in
        while !condition() {
            try Task.checkCancellation()
            await Task.yield()
        }
    }
}

@MainActor
private func waitForHostedVerification<Content: View>(
    host: SwiftUIRuntimeHost<Content>,
    condition: @escaping @MainActor @Sendable () -> Bool
) async throws {
    try await withSwiftUITestTimeout("hosted verification state", seconds: 2) { @MainActor in
        while !condition() {
            try Task.checkCancellation()
            await host.settle(cycles: 1)
        }
    }
}

@MainActor
private func acceptsVerificationInput(_ textField: UITextField) -> Bool? {
    textField.delegate?.textField?(
        textField,
        shouldChangeCharactersIn: NSRange(location: 0, length: 0),
        replacementString: "5"
    )
}

private struct HostedEmailVerificationStringsProvider: EmailVerificationStringsProvider {
    let strings: VerificationContentStream<EmailVerificationStrings?>

    func getStrings(params: EmailVerificationStringsParams) -> AsyncStream<EmailVerificationStrings?> {
        strings.makeStream()
    }
}

private struct HostedEmailVerificationAPIController: EmailVerificationAPIController {
    let challenge: VerificationChallenge

    func complete(code: String) async -> APIResult<AccessOrProofToken, EmailVerificationCompleteAPIFailure> { .canceled }
    func resend() async -> APIResult<Void, EmailVerificationResendAPIFailure> { .canceled }
    func cancel(reason: Reason) async -> APIResult<Void, EmailVerificationCancelAPIFailure> { .canceled }
}

private struct HostedPhoneVerificationStringsProvider: PhoneVerificationStringsProvider {
    let strings: VerificationContentStream<PhoneVerificationStrings?>

    func getStrings(params: PhoneVerificationStringsParams) -> AsyncStream<PhoneVerificationStrings?> {
        strings.makeStream()
    }
}

private struct HostedPhoneVerificationAPIController: PhoneVerificationAPIController {
    let challenge: VerificationChallenge

    func complete(code: String) async -> APIResult<AccessOrProofToken, PhoneVerificationCompleteAPIFailure> { .canceled }
    func resend() async -> APIResult<Void, PhoneVerificationResendAPIFailure> { .canceled }
    func cancel(reason: Reason) async -> APIResult<Void, PhoneVerificationCancelAPIFailure> { .canceled }
}

private final class VerificationContentStream<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [AsyncStream<Value>.Continuation] = []
    private var canceledSubscriptions = 0

    var subscriptionCount: Int { lock.withLock { continuations.count } }
    var cancellationCount: Int { lock.withLock { canceledSubscriptions } }

    func makeStream() -> AsyncStream<Value> {
        AsyncStream { continuation in
            continuation.onTermination = { [weak self] termination in
                guard case .cancelled = termination, let self else { return }
                self.lock.withLock { self.canceledSubscriptions += 1 }
            }
            lock.withLock { continuations.append(continuation) }
        }
    }

    func yield(_ value: Value, subscription: Int = 0) {
        lock.withLock { continuations[subscription] }.yield(value)
    }

    func finish(subscription: Int = 0) {
        lock.withLock { continuations[subscription] }.finish()
    }
}
