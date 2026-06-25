import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

struct OperationUIStartupRuntimeTests {

    @Test func `Core login ID collect without UI settles as integration UI failure`() async throws {
        let operation = makeLoginIDCollectOperation(ui: NoopLoginIDCollectUI())

        let controller = operation.start(params: LoginIDCollectOperationParams())
        let result = try await withOperationTimeout("login ID collect no UI") { await controller.whenSettled() }

        let failure = try requireOperationFailure(result)
        try assertLoginIDUIFailure(failure, contains: "No UI implementation registered for LoginIDCollectUI")
    }

    @Test func `Core email verification without UI settles as integration UI failure`() async throws {
        let api = FakeEmailVerificationAPI(
            apiController: FakeEmailVerificationAPIController(completeResult: .success(.accessToken(testAccessToken())))
        )
        let operation = makeEmailOperation(ui: NoopEmailVerificationUI(), api: api)

        let controller = operation.start(params: EmailVerificationOperationParams(loginID: testLoginID()))
        let result = try await withOperationTimeout("email verification no UI") { await controller.whenSettled() }

        let failure = try requireOperationFailure(result)
        try assertEmailUIFailure(failure, contains: "No UI implementation registered for EmailVerificationUI")
    }

    @Test func `Core phone verification without UI settles as integration UI failure`() async throws {
        let api = FakePhoneVerificationAPI(
            apiController: FakePhoneVerificationAPIController(completeResult: .success(.accessToken(testAccessToken())))
        )
        let operation = makePhoneOperation(ui: NoopPhoneVerificationUI(), api: api)

        let controller = operation.start(
            params: PhoneVerificationOperationParams(loginID: testLoginID("+15551234567", type: .phoneNumber))
        )
        let result = try await withOperationTimeout("phone verification no UI") { await controller.whenSettled() }

        let failure = try requireOperationFailure(result)
        try assertPhoneUIFailure(failure, contains: "No UI implementation registered for PhoneVerificationUI")
    }

    @Test func `Login ID collect UI startup error keeps one terminal result`() async throws {
        let ui = StartupFailingLoginIDCollectUI(
            error: .ui(errorCode: .integrationError, message: "container unavailable")
        )
        let operation = makeLoginIDCollectOperation(ui: ui)

        let controller = operation.start(params: LoginIDCollectOperationParams())
        let firstResult = try await withOperationTimeout("login ID collect UI startup error") {
            await controller.whenSettled()
        }
        controller.abort(reason: .userClose(details: "late abort"))
        let secondResult = try await withOperationTimeout("login ID collect second settlement") {
            await controller.whenSettled()
        }

        let firstFailure = try requireOperationFailure(firstResult)
        let secondFailure = try requireOperationFailure(secondResult)
        try assertLoginIDUIFailure(firstFailure, contains: "container unavailable")
        #expect(firstFailure.description == secondFailure.description)
        #expect(ui.startCount.get() == 1)
    }

    @Test func `Email verification UI startup error keeps one terminal result`() async throws {
        let ui = StartupFailingEmailVerificationUI(
            error: .ui(errorCode: .integrationError, message: "container unavailable")
        )
        let api = FakeEmailVerificationAPI(
            apiController: FakeEmailVerificationAPIController(completeResult: .success(.accessToken(testAccessToken())))
        )
        let operation = makeEmailOperation(ui: ui, api: api)

        let controller = operation.start(params: EmailVerificationOperationParams(loginID: testLoginID()))
        let firstResult = try await withOperationTimeout("email verification UI startup error") {
            await controller.whenSettled()
        }
        controller.abort(reason: .userClose(details: "late abort"))
        let secondResult = try await withOperationTimeout("email verification second settlement") {
            await controller.whenSettled()
        }

        let firstFailure = try requireOperationFailure(firstResult)
        let secondFailure = try requireOperationFailure(secondResult)
        try assertEmailUIFailure(firstFailure, contains: "container unavailable")
        #expect(firstFailure.description == secondFailure.description)
        #expect(ui.startCount.get() == 1)
    }

    @Test func `Phone verification UI startup error keeps one terminal result`() async throws {
        let ui = StartupFailingPhoneVerificationUI(
            error: .ui(errorCode: .integrationError, message: "container unavailable")
        )
        let api = FakePhoneVerificationAPI(
            apiController: FakePhoneVerificationAPIController(completeResult: .success(.accessToken(testAccessToken())))
        )
        let operation = makePhoneOperation(ui: ui, api: api)

        let controller = operation.start(
            params: PhoneVerificationOperationParams(loginID: testLoginID("+15551234567", type: .phoneNumber))
        )
        let firstResult = try await withOperationTimeout("phone verification UI startup error") {
            await controller.whenSettled()
        }
        controller.abort(reason: .userClose(details: "late abort"))
        let secondResult = try await withOperationTimeout("phone verification second settlement") {
            await controller.whenSettled()
        }

        let firstFailure = try requireOperationFailure(firstResult)
        let secondFailure = try requireOperationFailure(secondResult)
        try assertPhoneUIFailure(firstFailure, contains: "container unavailable")
        #expect(firstFailure.description == secondFailure.description)
        #expect(ui.startCount.get() == 1)
    }

    @Test func `Email verification missing OTP challenge settles as integration error`() async throws {
        let ui = FakeEmailVerificationUI()
        let api = FakeEmailVerificationAPI(
            apiController: FakeEmailVerificationAPIController(
                challenge: verificationChallengeWithoutOTP(),
                completeResult: .success(.accessToken(testAccessToken()))
            )
        )
        let operation = makeEmailOperation(ui: ui, api: api)

        let controller = operation.start(params: EmailVerificationOperationParams(loginID: testLoginID()))
        let result = try await withOperationTimeout("email verification missing OTP") { await controller.whenSettled() }

        let failure = try requireOperationFailure(result)
        try assertEmailUnexpectedMissingOTPFailure(failure)
        #expect(api.params.get().count == 1)
    }

    @Test func `Phone verification missing OTP challenge settles as integration error`() async throws {
        let ui = FakePhoneVerificationUI()
        let api = FakePhoneVerificationAPI(
            apiController: FakePhoneVerificationAPIController(
                challenge: verificationChallengeWithoutOTP(),
                completeResult: .success(.accessToken(testAccessToken()))
            )
        )
        let operation = makePhoneOperation(ui: ui, api: api)

        let controller = operation.start(
            params: PhoneVerificationOperationParams(loginID: testLoginID("+15551234567", type: .phoneNumber))
        )
        let result = try await withOperationTimeout("phone verification missing OTP") { await controller.whenSettled() }

        let failure = try requireOperationFailure(result)
        try assertPhoneUnexpectedMissingOTPFailure(failure)
        #expect(api.params.get().count == 1)
    }

    private func makeLoginIDCollectOperation(ui: any LoginIDCollectUI) -> LoginIDCollectOperationImpl {
        LoginIDCollectOperationImpl(
            operationType: .loginIDCollect,
            operationRegistry: OperationRegistryImpl(logger: nil),
            loginIDConfig: FakeLoginIDConfigurationProvider(
                configuration: LoginIDConfiguration(
                    supportedTypes: [.email, .phoneNumber, .userName],
                    validationRegexes: [.email: nil, .phoneNumber: nil, .userName: nil]
                )
            ),
            loginIDValidator: FakeLoginIDValidator(),
            ui: ui,
            taskScope: testTaskScope(),
            errorStringsProvider: nil,
            context: nil,
            logger: nil
        )
    }

    private func makeEmailOperation(ui: any EmailVerificationUI, api: FakeEmailVerificationAPI) -> EmailVerificationOperationImpl {
        EmailVerificationOperationImpl(
            operationType: .emailVerification,
            operationRegistry: OperationRegistryImpl(logger: nil),
            ui: ui,
            api: api,
            taskScope: testTaskScope(),
            errorStringsProvider: nil,
            context: nil,
            loginIDValidator: FakeLoginIDValidator(),
            logger: nil
        )
    }

    private func makePhoneOperation(ui: any PhoneVerificationUI, api: FakePhoneVerificationAPI) -> PhoneVerificationOperationImpl {
        PhoneVerificationOperationImpl(
            operationType: .phoneNumberVerification,
            operationRegistry: OperationRegistryImpl(logger: nil),
            ui: ui,
            api: api,
            taskScope: testTaskScope(),
            errorStringsProvider: nil,
            context: nil,
            loginIDValidator: FakeLoginIDValidator(),
            logger: nil
        )
    }

    private func verificationChallengeWithoutOTP() -> VerificationChallenge {
        VerificationChallenge(
            challengeID: ChallengeID("missing-otp-challenge"),
            resendPolicy: .init(allow: true, attempts: 3, debounce: 1),
            timeout: Timeout(milliseconds: 10_000),
            attempts: 3,
            methods: .init(otp: nil, magicLink: .init()),
            channel: OperationChannel(channel: "user@example.test", id: "channel-id")
        )
    }
}

private final class StartupFailingLoginIDCollectUI: LoginIDCollectUI, @unchecked Sendable {
    let startCount = Locked(0)
    private let error: LoginIDCollectOperationFailure.Integration

    init(error: LoginIDCollectOperationFailure.Integration) {
        self.error = error
    }

    @MainActor
    func start(controller: any LoginIDCollectOperationController) -> LoginIDCollectOperationFailure.Integration? {
        startCount.mutate { $0 += 1 }
        return error
    }
}

private final class StartupFailingEmailVerificationUI: EmailVerificationUI, @unchecked Sendable {
    let startCount = Locked(0)
    private let error: EmailVerificationOperationFailure.Integration

    init(error: EmailVerificationOperationFailure.Integration) {
        self.error = error
    }

    @MainActor
    func start(controller: any EmailVerificationOperationController) -> EmailVerificationOperationFailure.Integration? {
        startCount.mutate { $0 += 1 }
        return error
    }
}

private final class StartupFailingPhoneVerificationUI: PhoneVerificationUI, @unchecked Sendable {
    let startCount = Locked(0)
    private let error: PhoneVerificationOperationFailure.Integration

    init(error: PhoneVerificationOperationFailure.Integration) {
        self.error = error
    }

    @MainActor
    func start(controller: any PhoneVerificationOperationController) -> PhoneVerificationOperationFailure.Integration? {
        startCount.mutate { $0 += 1 }
        return error
    }
}

private func assertLoginIDUIFailure(
    _ failure: LoginIDCollectOperationFailure,
    contains expectedMessage: String,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws {
    let (errorCode, message) = try #require(loginIDUIFailurePayload(from: failure), sourceLocation: sourceLocation)
    #expect(errorCode == .integrationError, sourceLocation: sourceLocation)
    #expect(message.contains(expectedMessage), sourceLocation: sourceLocation)
}

private func assertEmailUIFailure(
    _ failure: EmailVerificationOperationFailure,
    contains expectedMessage: String,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws {
    let (errorCode, message) = try #require(emailUIFailurePayload(from: failure), sourceLocation: sourceLocation)
    #expect(errorCode == .integrationError, sourceLocation: sourceLocation)
    #expect(message.contains(expectedMessage), sourceLocation: sourceLocation)
}

private func assertPhoneUIFailure(
    _ failure: PhoneVerificationOperationFailure,
    contains expectedMessage: String,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws {
    let (errorCode, message) = try #require(phoneUIFailurePayload(from: failure), sourceLocation: sourceLocation)
    #expect(errorCode == .integrationError, sourceLocation: sourceLocation)
    #expect(message.contains(expectedMessage), sourceLocation: sourceLocation)
}

private func assertEmailUnexpectedMissingOTPFailure(
    _ failure: EmailVerificationOperationFailure,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws {
    let (errorCode, message) = try #require(emailUnexpectedFailurePayload(from: failure), sourceLocation: sourceLocation)
    #expect(errorCode == .integrationError, sourceLocation: sourceLocation)
    #expect(message.contains("OTP challenge method missing"), sourceLocation: sourceLocation)
}

private func assertPhoneUnexpectedMissingOTPFailure(
    _ failure: PhoneVerificationOperationFailure,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws {
    let (errorCode, message) = try #require(phoneUnexpectedFailurePayload(from: failure), sourceLocation: sourceLocation)
    #expect(errorCode == .integrationError, sourceLocation: sourceLocation)
    #expect(message.contains("OTP challenge method missing"), sourceLocation: sourceLocation)
}

private func loginIDUIFailurePayload(from failure: LoginIDCollectOperationFailure) -> (ErrorCode, String)? {
    guard case .integration(.ui(let errorCode, let message, _)) = failure else { return nil }
    return (errorCode, message)
}

private func emailUIFailurePayload(from failure: EmailVerificationOperationFailure) -> (ErrorCode, String)? {
    guard case .integration(.ui(let errorCode, let message, _)) = failure else { return nil }
    return (errorCode, message)
}

private func phoneUIFailurePayload(from failure: PhoneVerificationOperationFailure) -> (ErrorCode, String)? {
    guard case .integration(.ui(let errorCode, let message, _)) = failure else { return nil }
    return (errorCode, message)
}

private func emailUnexpectedFailurePayload(from failure: EmailVerificationOperationFailure) -> (ErrorCode, String)? {
    guard case .unexpected(let errorCode, let message, _, _) = failure else { return nil }
    return (errorCode, message)
}

private func phoneUnexpectedFailurePayload(from failure: PhoneVerificationOperationFailure) -> (ErrorCode, String)? {
    guard case .unexpected(let errorCode, let message, _, _) = failure else { return nil }
    return (errorCode, message)
}
