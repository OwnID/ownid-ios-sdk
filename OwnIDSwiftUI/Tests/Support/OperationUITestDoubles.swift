import Foundation

@_spi(OwnIDInternal) @testable import OwnIDCore

final class CapturingOperationUIContainer: OperationUIContainer, @unchecked Sendable {
    private let lock = NSLock()
    private var operationIDs: [OperationID] = []

    var shownOperationIDs: [OperationID] {
        lock.withLock { operationIDs }
    }

    @MainActor
    func show<Controller: OperationController>(controller: Controller) {
        lock.withLock { operationIDs.append(controller.operationID) }
    }
}

final class StubLoginIDCollectOperationController: LoginIDCollectOperationController, @unchecked Sendable {
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

final class StubEmailVerificationOperationController: EmailVerificationOperationController, @unchecked Sendable {
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

final class StubPhoneVerificationOperationController: PhoneVerificationOperationController, @unchecked Sendable {
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
