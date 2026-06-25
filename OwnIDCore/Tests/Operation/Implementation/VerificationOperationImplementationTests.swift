import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

struct VerificationOperationImplementationTests {
    private let startupTimeout: UInt64 = 15
    private let delayedTerminalTimeout: UInt64 = 5
    private let cleanupTimeout: UInt64 = 5

    @Test func `Email verification accepts email target without hint and exposes API challenge channel`() async throws {
        let challenge = testVerificationChallenge(
            channel: OperationChannel(channel: "api-email-channel@example.test", id: "api-email-channel-id")
        )
        let api = FakeEmailVerificationAPI(
            apiController: FakeEmailVerificationAPIController(
                challenge: challenge,
                completeResult: .success(.accessToken(testAccessToken()))
            )
        )
        let ui = FakeEmailVerificationUI()
        let operation = makeEmailOperation(api: api, ui: ui)
        let loginID = testLoginID("typed-email@example.test", type: .email)

        assertAvailable(await operation.availability(params: EmailVerificationOperationParams(loginID: loginID)))
        operation.start(params: EmailVerificationOperationParams(loginID: loginID))
        let uiController = try await withOperationTimeout("email UI controller", seconds: startupTimeout) {
            try await ui.controller.waitUnlessCancelled()
        }
        let activeState = try await nextEmailActiveState(from: uiController, where: { !$0.isBusy })
        let startParams = try #require(api.params.get().first ?? nil)

        #expect(startParams.loginID == loginID)
        #expect(startParams.loginIDHintID == nil)
        #expect(activeState.challenge.channel == challenge.channel)
    }

    @Test func `Phone verification accepts phone target without hint and exposes API challenge channel`() async throws {
        let challenge = testVerificationChallenge(
            channel: OperationChannel(channel: "+1******0100", id: "api-phone-channel-id")
        )
        let api = FakePhoneVerificationAPI(
            apiController: FakePhoneVerificationAPIController(
                challenge: challenge,
                completeResult: .success(.accessToken(testAccessToken()))
            )
        )
        let ui = FakePhoneVerificationUI()
        let operation = makePhoneOperation(api: api, ui: ui)
        let loginID = testLoginID("+15550100100", type: .phoneNumber)

        assertAvailable(await operation.availability(params: PhoneVerificationOperationParams(loginID: loginID)))
        operation.start(params: PhoneVerificationOperationParams(loginID: loginID))
        let uiController = try await withOperationTimeout("phone UI controller", seconds: startupTimeout) {
            try await ui.controller.waitUnlessCancelled()
        }
        let activeState = try await nextPhoneActiveState(from: uiController, where: { !$0.isBusy })
        let startParams = try #require(api.params.get().first ?? nil)

        #expect(startParams.loginID == loginID)
        #expect(startParams.loginIDHintID == nil)
        #expect(activeState.challenge.channel == challenge.channel)
    }

    @Test func `Username verification forwards selected hint and exposes API challenge channel`() async throws {
        let username = testLoginID("account-handle", type: .userName)
        let emailChallenge = testVerificationChallenge(
            channel: OperationChannel(channel: "masked-email-from-api@example.test", id: "api-email-selected")
        )
        let emailAPI = FakeEmailVerificationAPI(
            apiController: FakeEmailVerificationAPIController(
                challenge: emailChallenge,
                completeResult: .success(.accessToken(testAccessToken("email-token")))
            )
        )
        let emailUI = FakeEmailVerificationUI()
        let emailOperation = makeEmailOperation(api: emailAPI, ui: emailUI)

        emailOperation.start(
            params: EmailVerificationOperationParams(loginID: username, loginIDHintID: "selected-email-channel")
        )
        let emailController = try await withOperationTimeout("username email UI controller", seconds: startupTimeout) {
            try await emailUI.controller.waitUnlessCancelled()
        }
        let emailState = try await nextEmailActiveState(from: emailController, where: { !$0.isBusy })
        let emailStartParams = try #require(emailAPI.params.get().first ?? nil)

        #expect(emailStartParams.loginID == username)
        #expect(emailStartParams.loginIDHintID == "selected-email-channel")
        #expect(emailState.challenge.channel == emailChallenge.channel)

        let phoneChallenge = testVerificationChallenge(
            channel: OperationChannel(channel: "+1******0200", id: "api-phone-selected")
        )
        let phoneAPI = FakePhoneVerificationAPI(
            apiController: FakePhoneVerificationAPIController(
                challenge: phoneChallenge,
                completeResult: .success(.accessToken(testAccessToken("phone-token")))
            )
        )
        let phoneUI = FakePhoneVerificationUI()
        let phoneOperation = makePhoneOperation(api: phoneAPI, ui: phoneUI)

        phoneOperation.start(
            params: PhoneVerificationOperationParams(loginID: username, loginIDHintID: "selected-phone-channel")
        )
        let phoneController = try await withOperationTimeout("username phone UI controller", seconds: startupTimeout) {
            try await phoneUI.controller.waitUnlessCancelled()
        }
        let phoneState = try await nextPhoneActiveState(from: phoneController, where: { !$0.isBusy })
        let phoneStartParams = try #require(phoneAPI.params.get().first ?? nil)

        #expect(phoneStartParams.loginID == username)
        #expect(phoneStartParams.loginIDHintID == "selected-phone-channel")
        #expect(phoneState.challenge.channel == phoneChallenge.channel)
    }

    @Test func `Username verification rejects missing or blank hint before API start`() async throws {
        let username = testLoginID("account-handle", type: .userName)
        let emailCases: [EmailVerificationOperationParams] = [
            EmailVerificationOperationParams(loginID: username, loginIDHintID: nil),
            EmailVerificationOperationParams(loginID: username, loginIDHintID: " \n "),
        ]
        for params in emailCases {
            let api = FakeEmailVerificationAPI(
                apiController: FakeEmailVerificationAPIController(completeResult: .success(.accessToken(testAccessToken())))
            )
            let operation = makeEmailOperation(api: api, ui: FakeEmailVerificationUI())
            assertUnavailable(await operation.availability(params: params))

            let failure = try await requireOperationFailure(
                withOperationTimeout("username email hint rejection", seconds: startupTimeout) {
                    await operation.start(params: params).whenSettled()
                }
            )

            #expect(failure.errorCode == .loginIDTypeNotSupported)
            #expect(api.params.get().isEmpty)
        }

        let phoneCases: [PhoneVerificationOperationParams] = [
            PhoneVerificationOperationParams(loginID: username, loginIDHintID: nil),
            PhoneVerificationOperationParams(loginID: username, loginIDHintID: "\t "),
        ]
        for params in phoneCases {
            let api = FakePhoneVerificationAPI(
                apiController: FakePhoneVerificationAPIController(completeResult: .success(.accessToken(testAccessToken())))
            )
            let operation = makePhoneOperation(api: api, ui: FakePhoneVerificationUI())
            assertUnavailable(await operation.availability(params: params))

            let failure = try await requireOperationFailure(
                withOperationTimeout("username phone hint rejection", seconds: startupTimeout) {
                    await operation.start(params: params).whenSettled()
                }
            )

            #expect(failure.errorCode == .loginIDTypeNotSupported)
            #expect(api.params.get().isEmpty)
        }
    }

    @Test func `Email wrong OTP stays active with UI error`() async throws {
        let apiController = FakeEmailVerificationAPIController(
            completeResult: .failure(
                .badRequest(
                    .wrongCode(errorCode: .verificationCodeWrong, message: "Wrong code", challengeID: ChallengeID("email-challenge"))
                )
            )
        )
        let ui = FakeEmailVerificationUI()
        let operation = makeEmailOperation(api: FakeEmailVerificationAPI(apiController: apiController), ui: ui)

        operation.start(params: EmailVerificationOperationParams(loginID: testLoginID()))
        let uiController = try await withOperationTimeout("email UI controller", seconds: startupTimeout) {
            try await ui.controller.waitUnlessCancelled()
        }
        let initialState = try await nextEmailActiveState(from: uiController, where: { !$0.isBusy && $0.error == nil })

        initialState.onCodeEntered("111111")
        let errorState = try await nextEmailActiveState(
            from: uiController,
            where: { !$0.isBusy && $0.error?.errorCode == .verificationCodeWrong }
        )

        #expect(errorState.error?.errorCode == .verificationCodeWrong)
        #expect(apiController.completedCodes.get() == ["111111"])

        errorState.onCancel()
        _ = try await withOperationTimeout("email wrong OTP server cancellation", seconds: cleanupTimeout) {
            try await apiController.cancelReason.waitUnlessCancelled()
        }
        _ = try requireOperationCancellation(try await nextEmailCompletedResult(from: uiController))
    }

    @Test func `Email maximum attempts becomes terminal failure`() async throws {
        let apiController = FakeEmailVerificationAPIController(
            completeResult: .failure(
                .badRequest(
                    .maximumAttemptsReached(
                        errorCode: .maximumAttemptsReached,
                        message: "Maximum attempts reached",
                        challengeID: ChallengeID("email-challenge")
                    )
                )
            )
        )
        let ui = FakeEmailVerificationUI()
        let operation = makeEmailOperation(api: FakeEmailVerificationAPI(apiController: apiController), ui: ui)

        operation.start(params: EmailVerificationOperationParams(loginID: testLoginID()))
        let uiController = try await withOperationTimeout("email UI controller", seconds: startupTimeout) {
            try await ui.controller.waitUnlessCancelled()
        }
        let activeState = try await nextEmailActiveState(from: uiController, where: { !$0.isBusy })

        activeState.onCodeEntered("222222")
        _ = try await nextEmailActiveState(
            from: uiController,
            where: { !$0.isBusy && $0.error?.errorCode == .maximumAttemptsReached }
        )
        let result = try await nextEmailCompletedResult(from: uiController, seconds: delayedTerminalTimeout)

        let failure = try requireOperationFailure(result)
        let cancelReason = try await withOperationTimeout(
            "email maximum attempts server cancellation",
            seconds: delayedTerminalTimeout
        ) {
            try await apiController.cancelReason.waitUnlessCancelled()
        }
        #expect(failure.errorCode == .maximumAttemptsReached)
        #expect(failure.message == "Maximum attempts reached")
        #expect(apiController.completedCodes.get() == ["222222"])
        #expect(cancelReason.description == Reason.userClose(details: "Maximum attempts reached").description)
        #expect(apiController.cancelReasons.get().map(\.description) == [cancelReason.description])
    }

    @Test func `Phone wrong OTP stays active with UI error`() async throws {
        let apiController = FakePhoneVerificationAPIController(
            completeResult: .failure(
                .badRequest(
                    .wrongCode(errorCode: .verificationCodeWrong, message: "Wrong code", challengeID: ChallengeID("phone-challenge"))
                )
            )
        )
        let ui = FakePhoneVerificationUI()
        let operation = makePhoneOperation(api: FakePhoneVerificationAPI(apiController: apiController), ui: ui)

        operation.start(
            params: PhoneVerificationOperationParams(loginID: testLoginID("+15551234567", type: .phoneNumber))
        )
        let uiController = try await withOperationTimeout("phone UI controller", seconds: startupTimeout) {
            try await ui.controller.waitUnlessCancelled()
        }
        let initialState = try await nextPhoneActiveState(from: uiController, where: { !$0.isBusy && $0.error == nil })

        initialState.onCodeEntered("333333")
        let errorState = try await nextPhoneActiveState(
            from: uiController,
            where: { !$0.isBusy && $0.error?.errorCode == .verificationCodeWrong }
        )

        #expect(errorState.error?.errorCode == .verificationCodeWrong)
        #expect(apiController.completedCodes.get() == ["333333"])

        errorState.onCancel()
        _ = try await withOperationTimeout("phone wrong OTP server cancellation", seconds: cleanupTimeout) {
            try await apiController.cancelReason.waitUnlessCancelled()
        }
        _ = try requireOperationCancellation(try await nextPhoneCompletedResult(from: uiController))
    }

    @Test func `Phone maximum attempts becomes terminal failure`() async throws {
        let apiController = FakePhoneVerificationAPIController(
            completeResult: .failure(
                .badRequest(
                    .maximumAttemptsReached(
                        errorCode: .maximumAttemptsReached,
                        message: "Maximum attempts reached",
                        challengeID: ChallengeID("phone-challenge")
                    )
                )
            )
        )
        let ui = FakePhoneVerificationUI()
        let operation = makePhoneOperation(api: FakePhoneVerificationAPI(apiController: apiController), ui: ui)

        operation.start(
            params: PhoneVerificationOperationParams(loginID: testLoginID("+15551234567", type: .phoneNumber))
        )
        let uiController = try await withOperationTimeout("phone UI controller", seconds: startupTimeout) {
            try await ui.controller.waitUnlessCancelled()
        }
        let activeState = try await nextPhoneActiveState(from: uiController, where: { !$0.isBusy })

        activeState.onCodeEntered("444444")
        _ = try await nextPhoneActiveState(
            from: uiController,
            where: { !$0.isBusy && $0.error?.errorCode == .maximumAttemptsReached }
        )
        let result = try await nextPhoneCompletedResult(from: uiController, seconds: delayedTerminalTimeout)

        let failure = try requireOperationFailure(result)
        let cancelReason = try await withOperationTimeout(
            "phone maximum attempts server cancellation",
            seconds: delayedTerminalTimeout
        ) {
            try await apiController.cancelReason.waitUnlessCancelled()
        }
        #expect(failure.errorCode == .maximumAttemptsReached)
        #expect(failure.message == "Maximum attempts reached")
        #expect(apiController.completedCodes.get() == ["444444"])
        #expect(cancelReason.description == Reason.userClose(details: "Maximum attempts reached").description)
        #expect(apiController.cancelReasons.get().map(\.description) == [cancelReason.description])
    }

    private func makeEmailOperation(api: FakeEmailVerificationAPI, ui: FakeEmailVerificationUI) -> EmailVerificationOperationImpl {
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

    private func makePhoneOperation(api: FakePhoneVerificationAPI, ui: FakePhoneVerificationUI) -> PhoneVerificationOperationImpl {
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
}
