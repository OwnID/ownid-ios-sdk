import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

struct OperationUIContractTests {

    @Test func `Login ID collection UI state equality ignores callbacks`() {
        let first = LoginIDCollectUIState(
            loginIDValue: "user@example.com",
            collectableLoginIDTypes: [.email, .phoneNumber],
            error: UIError(errorCode: .loginIDValidationFailed, localizedMessage: "Invalid login ID"),
            onLoginIDChange: { _ in },
            onContinue: {},
            onCancel: {}
        )
        let second = LoginIDCollectUIState(
            loginIDValue: "user@example.com",
            collectableLoginIDTypes: [.email, .phoneNumber],
            error: UIError(errorCode: .loginIDValidationFailed, localizedMessage: "Invalid login ID"),
            onLoginIDChange: { _ in },
            onContinue: {},
            onCancel: {}
        )
        let differentValue = LoginIDCollectUIState(
            loginIDValue: "other@example.com",
            collectableLoginIDTypes: [.email, .phoneNumber],
            error: UIError(errorCode: .loginIDValidationFailed, localizedMessage: "Invalid login ID"),
            onLoginIDChange: { _ in },
            onContinue: {},
            onCancel: {}
        )

        #expect(first == second)
        #expect(first != differentValue)
    }

    @Test func `Verification UI state equality ignores callbacks`() {
        let challenge = testVerificationChallenge()
        let email = EmailVerificationUIState(
            challenge: challenge,
            isBusy: true,
            error: UIError(errorCode: .verificationCodeWrong, localizedMessage: "Invalid code"),
            onCodeEntered: { _ in },
            onCancel: {},
            onNotYou: {},
            onResend: {}
        )
        let emailWithDifferentCallbacks = EmailVerificationUIState(
            challenge: challenge,
            isBusy: true,
            error: UIError(errorCode: .verificationCodeWrong, localizedMessage: "Invalid code"),
            onCodeEntered: { _ in },
            onCancel: {},
            onNotYou: {},
            onResend: {}
        )
        let phone = PhoneVerificationUIState(
            challenge: challenge,
            isBusy: false,
            error: nil,
            onCodeEntered: { _ in },
            onCancel: {},
            onNotYou: {},
            onResend: {}
        )
        let phoneWithDifferentCallbacks = PhoneVerificationUIState(
            challenge: challenge,
            isBusy: false,
            error: nil,
            onCodeEntered: { _ in },
            onCancel: {},
            onNotYou: {},
            onResend: {}
        )
        let busyPhone = PhoneVerificationUIState(
            challenge: challenge,
            isBusy: true,
            error: nil,
            onCodeEntered: { _ in },
            onCancel: {},
            onNotYou: {},
            onResend: {}
        )

        #expect(email == emailWithDifferentCallbacks)
        #expect(phone == phoneWithDifferentCallbacks)
        #expect(phone != busyPhone)
    }

    @MainActor
    @Test(arguments: NoopUIStartupCase.allCases)
    func `Noop UI startup returns integration failures without throwing`(startupCase: NoopUIStartupCase) throws {
        try expectUIIntegrationFailure(startupCase.start(), mentions: startupCase.expectedType)
    }
}

enum NoopUIStartupCase: CaseIterable, Sendable {
    case loginIDCollect
    case emailVerification
    case phoneVerification

    var expectedType: String {
        switch self {
        case .loginIDCollect:
            "LoginIDCollectUI"
        case .emailVerification:
            "EmailVerificationUI"
        case .phoneVerification:
            "PhoneVerificationUI"
        }
    }

    @MainActor
    func start() -> UIFailureDetails? {
        switch self {
        case .loginIDCollect:
            guard let failure = NoopLoginIDCollectUI().start(controller: StubLoginIDCollectOperationController()) else {
                return nil
            }
            return uiFailureDetails(from: failure)
        case .emailVerification:
            guard let failure = NoopEmailVerificationUI().start(controller: StubEmailVerificationOperationController()) else {
                return nil
            }
            return uiFailureDetails(from: failure)
        case .phoneVerification:
            guard let failure = NoopPhoneVerificationUI().start(controller: StubPhoneVerificationOperationController()) else {
                return nil
            }
            return uiFailureDetails(from: failure)
        }
    }
}

struct UIFailureDetails {
    let errorCode: ErrorCode
    let message: String
    let underlyingError: (any Error & Sendable)?
}

private func expectUIIntegrationFailure(
    _ details: UIFailureDetails?,
    mentions expectedType: String,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws {
    let details = try #require(details, "Expected UI integration failure", sourceLocation: sourceLocation)
    #expect(details.errorCode == .integrationError, sourceLocation: sourceLocation)
    #expect(details.message.contains(expectedType), sourceLocation: sourceLocation)
    #expect(details.underlyingError == nil, sourceLocation: sourceLocation)
}

private func uiFailureDetails(from failure: LoginIDCollectOperationFailure.Integration) -> UIFailureDetails? {
    guard case .ui(let errorCode, let message, let underlyingError) = failure else { return nil }
    return UIFailureDetails(errorCode: errorCode, message: message, underlyingError: underlyingError)
}

private func uiFailureDetails(from failure: EmailVerificationOperationFailure.Integration) -> UIFailureDetails? {
    guard case .ui(let errorCode, let message, let underlyingError) = failure else { return nil }
    return UIFailureDetails(errorCode: errorCode, message: message, underlyingError: underlyingError)
}

private func uiFailureDetails(from failure: PhoneVerificationOperationFailure.Integration) -> UIFailureDetails? {
    guard case .ui(let errorCode, let message, let underlyingError) = failure else { return nil }
    return UIFailureDetails(errorCode: errorCode, message: message, underlyingError: underlyingError)
}

private final class StubLoginIDCollectOperationController: LoginIDCollectOperationController, @unchecked Sendable {
    let operationID = OperationID(type: .loginIDCollect, id: "login-id-collect")

    func abort(reason: Reason) {}

    func whenSettled() async -> OperationResult<LoginID, LoginIDCollectOperationFailure> {
        .canceled(.timeout)
    }

    @MainActor
    func stateStream() -> AsyncStream<LoginIDCollectOperationState> {
        AsyncStream { continuation in continuation.finish() }
    }
}

private final class StubEmailVerificationOperationController: EmailVerificationOperationController, @unchecked Sendable {
    let operationID = OperationID(type: .emailVerification, id: "email-verification")

    func abort(reason: Reason) {}

    func whenSettled() async -> OperationResult<AccessOrProofToken, EmailVerificationOperationFailure> {
        .canceled(.timeout)
    }

    @MainActor
    func stateStream() -> AsyncStream<EmailVerificationOperationState> {
        AsyncStream { continuation in continuation.finish() }
    }
}

private final class StubPhoneVerificationOperationController: PhoneVerificationOperationController, @unchecked Sendable {
    let operationID = OperationID(type: .phoneNumberVerification, id: "phone-verification")

    func abort(reason: Reason) {}

    func whenSettled() async -> OperationResult<AccessOrProofToken, PhoneVerificationOperationFailure> {
        .canceled(.timeout)
    }

    @MainActor
    func stateStream() -> AsyncStream<PhoneVerificationOperationState> {
        AsyncStream { continuation in continuation.finish() }
    }
}
