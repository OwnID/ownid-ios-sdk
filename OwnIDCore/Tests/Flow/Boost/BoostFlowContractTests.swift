import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

struct BoostFlowContractTests {

    @Test func `Boost login uses access token before login ID hints and last user fallback`() async throws {
        let tokenLoginID = FlowFixtures.loginID("token-user@example.com")
        let fallbackLoginID = FlowFixtures.loginID("fallback@example.com")
        let accessToken = FlowFixtures.accessToken(id: tokenLoginID.id, type: tokenLoginID.type)
        let repository = FlowRepositoryFake(lastUser: User(loginID: fallbackLoginID, authMethod: .otp))
        let harness = FlowTestHarness(loginResult: .success(FlowFixtures.loginSuccess(id: tokenLoginID.id)))
        var flowContext = BoostFlowContext()
        flowContext.accessToken = accessToken
        flowContext.loginID = FlowFixtures.loginID("explicit@example.com")

        let flow = BoostLoginFlowImpl(
            userRepository: repository,
            ownIDOperation: harness.operation,
            userJourney: nil,
            sessionCreate: nil,
            coder: harness.coder,
            taskScope: harness.taskScope,
            context: FlowFixtures.context(authz: .start("context@example.com", type: .email)),
            loginIDValidator: harness.validator,
            logger: nil
        )

        let result = await flow.start(flowContext).whenSettled()
        let response = try requireSuccess(result)
        let loginParams = try requireRecordedValue(harness.login.startParams, "Expected token login start params")

        #expect(response.loginID == tokenLoginID)
        #expect(response.authMethod == .immediate)
        #expect(loginParams.accessToken == accessToken)
        #expect(loginParams.loginID == nil)
        #expect(harness.loginIDCollect.startParams.isEmpty)
        #expect(repository.lastUserCallCount == 0)
    }

    @Test(
        arguments: [
            LoginIDOrderingCase(
                name: "flow typed login ID",
                flowContext: {
                    var context = BoostFlowContext()
                    context.loginID = FlowFixtures.loginID("flow@example.com")
                    return context
                },
                currentContext: nil,
                lastUser: User(loginID: FlowFixtures.loginID("last@example.com"), authMethod: .otp),
                expectedLoginID: FlowFixtures.loginID("flow@example.com"),
                expectedRawLoginID: nil,
                expectedLastUserReads: 0
            ),
            LoginIDOrderingCase(
                name: "flow raw login ID",
                flowContext: {
                    var context = BoostFlowContext()
                    context.loginID("raw-flow@example.com")
                    return context
                },
                currentContext: nil,
                lastUser: User(loginID: FlowFixtures.loginID("last@example.com"), authMethod: .otp),
                expectedLoginID: nil,
                expectedRawLoginID: "raw-flow@example.com",
                expectedLastUserReads: 0
            ),
            LoginIDOrderingCase(
                name: "current typed login ID",
                flowContext: { BoostFlowContext() },
                currentContext: FlowFixtures.context(authz: .start(FlowFixtures.loginID("current@example.com"))),
                lastUser: User(loginID: FlowFixtures.loginID("last@example.com"), authMethod: .otp),
                expectedLoginID: FlowFixtures.loginID("current@example.com"),
                expectedRawLoginID: nil,
                expectedLastUserReads: 0
            ),
            LoginIDOrderingCase(
                name: "current raw login ID",
                flowContext: { BoostFlowContext() },
                currentContext: FlowFixtures.context(authz: .start("raw-current@example.com")),
                lastUser: User(loginID: FlowFixtures.loginID("last@example.com"), authMethod: .otp),
                expectedLoginID: nil,
                expectedRawLoginID: "raw-current@example.com",
                expectedLastUserReads: 0
            ),
            LoginIDOrderingCase(
                name: "stored last user",
                flowContext: { BoostFlowContext() },
                currentContext: nil,
                lastUser: User(loginID: FlowFixtures.loginID("last@example.com"), authMethod: .otp),
                expectedLoginID: FlowFixtures.loginID("last@example.com"),
                expectedRawLoginID: nil,
                expectedLastUserReads: 1
            ),
            LoginIDOrderingCase(
                name: "ignore last user preserves empty fallback",
                flowContext: {
                    var context = BoostFlowContext()
                    context.ignoreLastUser = true
                    return context
                },
                currentContext: nil,
                lastUser: User(loginID: FlowFixtures.loginID("last@example.com"), authMethod: .otp),
                expectedLoginID: nil,
                expectedRawLoginID: nil,
                expectedLastUserReads: 0
            ),
        ]
    )
    func `Boost login ID source ordering without token`(_ testCase: LoginIDOrderingCase) async throws {
        let collected = FlowFixtures.loginID("collected@example.com")
        let repository = FlowRepositoryFake(lastUser: testCase.lastUser)
        let harness = FlowTestHarness(
            loginResult: .success(FlowFixtures.loginSuccess(id: collected.id)),
            loginIDCollectResult: .success(collected)
        )
        let flow = BoostLoginFlowImpl(
            userRepository: repository,
            ownIDOperation: harness.operation,
            userJourney: nil,
            sessionCreate: nil,
            coder: harness.coder,
            taskScope: harness.taskScope,
            context: testCase.currentContext,
            loginIDValidator: harness.validator,
            logger: nil
        )

        _ = await flow.start(testCase.flowContext()).whenSettled()
        let collectContext = try requireRecordedValue(
            harness.loginIDCollect.scopedContexts,
            "Expected login ID collect scoped context"
        )

        #expect(collectContext.loginID == testCase.expectedLoginID, "\(testCase.name)")
        #expect(collectContext.rawLoginID == testCase.expectedRawLoginID, "\(testCase.name)")
        #expect(repository.lastUserCallCount == testCase.expectedLastUserReads, "\(testCase.name)")
    }

    @Test(
        arguments: [
            SessionProviderCase(available: false, expectedSession: nil, expectedCreateCalls: 0),
            SessionProviderCase(available: true, expectedSession: "host-session", expectedCreateCalls: 1),
        ]
    )
    func `Boost login session provider availability controls callback`(_ testCase: SessionProviderCase) async throws {
        let loginID = FlowFixtures.loginID("session@example.com")
        let accessToken = FlowFixtures.accessToken(id: loginID.id)
        let sessionPayload = #"{"nested":{"raw":true}}"#
        let harness = FlowTestHarness(
            loginResult: .success(
                LoginResponse.success(
                    LoginResponse.Success(accessToken: accessToken, sessionPayload: sessionPayload)
                )
            ),
            loginIDCollectResult: .success(loginID)
        )
        let sessionCreate = FlowSessionCreateFake(available: testCase.available, session: "host-session")
        let flow = BoostLoginFlowImpl(
            ownIDOperation: harness.operation,
            userJourney: nil,
            sessionCreate: sessionCreate,
            coder: harness.coder,
            taskScope: harness.taskScope,
            context: nil,
            loginIDValidator: harness.validator,
            logger: nil
        )

        let response = try await requireSuccess(flow.start().whenSettled())

        #expect(response.sessionPayload == sessionPayload)
        #expect(response.session as? String == testCase.expectedSession)
        #expect(sessionCreate.createParams.count == testCase.expectedCreateCalls)
        let availabilityParams = try requireRecordedValue(
            sessionCreate.availabilityParams,
            "Expected session-create availability params"
        )
        #expect(availabilityParams.sessionPayload == sessionPayload)
        if let createParams = sessionCreate.createParams.first {
            #expect(createParams.sessionPayload == sessionPayload)
            #expect(createParams.accessToken == accessToken)
            #expect(createParams.loginID == loginID)
        }
    }

    @Test func `Boost create passkey returns login outcome for existing account`() async throws {
        let loginID = FlowFixtures.loginID("existing@example.com")
        let accessToken = FlowFixtures.accessToken(id: loginID.id)
        let sessionPayload = "raw-session-payload"
        let harness = FlowTestHarness(
            loginResult: .success(.success(LoginResponse.Success(accessToken: accessToken, sessionPayload: sessionPayload))),
            loginIDCollectResult: .success(loginID)
        )
        let flow = BoostCreatePasskeyFlowImpl(
            ownIDOperation: harness.operation,
            boostLoginFlow: FlowBoostLoginFlowFake(
                result: .failure(.unexpected(message: "child login should not start"))
            ),
            userJourney: nil,
            sessionCreate: nil,
            coder: harness.coder,
            taskScope: harness.taskScope,
            context: nil,
            loginIDValidator: harness.validator,
            logger: nil
        )

        let response = try await requireSuccess(flow.start(.empty).whenSettled())

        let login = try requireLoginOutcome(response)
        #expect(login.loginID == loginID)
        #expect(login.accessToken == accessToken)
        #expect(login.sessionPayload == sessionPayload)
        #expect(harness.passkeyAttestation.startParams.isEmpty)
    }

    @Test func `Boost create passkey returns create passkey outcome with attestation proof`() async throws {
        let loginID = FlowFixtures.loginID("new@example.com")
        let proofToken = ProofToken(token: "created-proof")
        let ownIdData = #"{"registration":"data"}"#
        let harness = FlowTestHarness(
            loginResult: .success(.accountNotFound(LoginResponse.AccountNotFound())),
            loginIDCollectResult: .success(loginID),
            passkeyAttestationResult: .success(
                FlowFixtures.attestationResponse(proofToken: proofToken, ownIdData: ownIdData)
            )
        )
        let flow = BoostCreatePasskeyFlowImpl(
            ownIDOperation: harness.operation,
            boostLoginFlow: FlowBoostLoginFlowFake(
                result: .failure(.unexpected(message: "child login should not start"))
            ),
            userJourney: nil,
            sessionCreate: nil,
            coder: harness.coder,
            taskScope: harness.taskScope,
            context: nil,
            loginIDValidator: harness.validator,
            logger: nil
        )

        let response = try await requireSuccess(flow.start(.empty).whenSettled())

        let created = try requireCreatePasskeyOutcome(response)
        #expect(created.loginID == loginID)
        #expect(created.proofToken == proofToken)
        #expect(created.ownIdData == ownIdData)
        let attestationParams = try requireRecordedValue(
            harness.passkeyAttestation.startParams,
            "Expected create-passkey attestation start params"
        )
        #expect(attestationParams.loginID == loginID)
    }

    @Test func `Boost create passkey delegates to login flow when passkey auth is required`() async throws {
        let loginID = FlowFixtures.loginID("returning@example.com")
        let childLogin = BoostFlowLoginResponse(
            loginID: loginID,
            authMethod: .passkey,
            accessToken: FlowFixtures.accessToken(id: loginID.id),
            sessionPayload: "child-session"
        )
        let childFlow = FlowBoostLoginFlowFake(result: .success(childLogin))
        let harness = FlowTestHarness(
            loginResult: .success(
                .authRequired(
                    LoginResponse.AuthRequired(
                        authRequirements: AuthRequirements(
                            targetScore: 1,
                            operations: [
                                OperationRequirement(score: 1, type: .passkeyAuth, channels: nil)
                            ]
                        )
                    )
                )
            ),
            loginIDCollectResult: .success(loginID)
        )
        let flow = BoostCreatePasskeyFlowImpl(
            ownIDOperation: harness.operation,
            boostLoginFlow: childFlow,
            userJourney: nil,
            sessionCreate: nil,
            coder: harness.coder,
            taskScope: harness.taskScope,
            context: nil,
            loginIDValidator: harness.validator,
            logger: nil
        )

        let response = try await requireSuccess(flow.start(.empty).whenSettled())

        let login = try requireLoginOutcome(response)
        #expect(login.loginID == loginID)
        #expect(login.authMethod == .passkey)
        #expect(childFlow.contexts.count == 1)
        #expect(harness.passkeyAttestation.startParams.isEmpty)
    }

    @Test func `Boost login auth-required starts matching email and phone verification routes`() async throws {
        let emailLoginID = FlowFixtures.loginID("email-route@example.test", type: .email)
        let emailHarness = FlowTestHarness(
            loginResult: .success(
                .authRequired(
                    LoginResponse.AuthRequired(
                        authRequirements: AuthRequirements(
                            targetScore: 1,
                            operations: [
                                OperationRequirement(
                                    score: 1,
                                    type: .emailVerification,
                                    channels: [OperationChannel(channel: "email-route@example.test", id: "email-route-channel")]
                                )
                            ]
                        )
                    )
                )
            ),
            loginIDCollectResult: .success(emailLoginID)
        )
        emailHarness.passkeyAttestation.availability = .unavailable("passkey creation unavailable")
        let emailFlow = BoostLoginFlowImpl(
            ownIDOperation: emailHarness.operation,
            userJourney: nil,
            sessionCreate: nil,
            coder: emailHarness.coder,
            taskScope: emailHarness.taskScope,
            context: nil,
            loginIDValidator: emailHarness.validator,
            logger: nil
        )

        _ = await emailFlow.start(.empty).whenSettled()
        let emailParams = try requireRecordedValue(
            emailHarness.emailVerification.startParams,
            "Expected email verification start params"
        )

        #expect(emailParams.loginID == emailLoginID)
        #expect(emailParams.loginIDHintID == "email-route-channel")
        #expect(emailHarness.phoneVerification.startParams.isEmpty)

        let phoneLoginID = FlowFixtures.loginID("+15550100300", type: .phoneNumber)
        let phoneHarness = FlowTestHarness(
            loginResult: .success(
                .authRequired(
                    LoginResponse.AuthRequired(
                        authRequirements: AuthRequirements(
                            targetScore: 1,
                            operations: [
                                OperationRequirement(
                                    score: 1,
                                    type: .phoneNumberVerification,
                                    channels: [OperationChannel(channel: "+1******0300", id: "phone-route-channel")]
                                )
                            ]
                        )
                    )
                )
            ),
            loginIDCollectResult: .success(phoneLoginID)
        )
        phoneHarness.passkeyAttestation.availability = .unavailable("passkey creation unavailable")
        let phoneFlow = BoostLoginFlowImpl(
            ownIDOperation: phoneHarness.operation,
            userJourney: nil,
            sessionCreate: nil,
            coder: phoneHarness.coder,
            taskScope: phoneHarness.taskScope,
            context: nil,
            loginIDValidator: phoneHarness.validator,
            logger: nil
        )

        _ = await phoneFlow.start(.empty).whenSettled()
        let phoneParams = try requireRecordedValue(
            phoneHarness.phoneVerification.startParams,
            "Expected phone verification start params"
        )

        #expect(phoneParams.loginID == phoneLoginID)
        #expect(phoneParams.loginIDHintID == "phone-route-channel")
        #expect(phoneHarness.emailVerification.startParams.isEmpty)
    }

    @Test func `Boost login auth-required forwards selected channel when login ID is username`() async throws {
        let username = FlowFixtures.loginID("account-handle", type: .userName)
        let emailHarness = FlowTestHarness(
            loginResult: .success(
                .authRequired(
                    LoginResponse.AuthRequired(
                        authRequirements: AuthRequirements(
                            targetScore: 1,
                            operations: [
                                OperationRequirement(
                                    score: 1,
                                    type: .emailVerification,
                                    channels: [OperationChannel(channel: "masked-email@example.test", id: "username-email-channel")]
                                )
                            ]
                        )
                    )
                )
            ),
            loginIDCollectResult: .success(username)
        )
        emailHarness.passkeyAttestation.availability = .unavailable("passkey creation unavailable")
        let emailFlow = BoostLoginFlowImpl(
            ownIDOperation: emailHarness.operation,
            userJourney: nil,
            sessionCreate: nil,
            coder: emailHarness.coder,
            taskScope: emailHarness.taskScope,
            context: nil,
            loginIDValidator: emailHarness.validator,
            logger: nil
        )

        _ = await emailFlow.start(.empty).whenSettled()
        let emailParams = try requireRecordedValue(
            emailHarness.emailVerification.startParams,
            "Expected username email verification start params"
        )

        #expect(emailParams.loginID == username)
        #expect(emailParams.loginIDHintID == "username-email-channel")
        #expect(emailHarness.phoneVerification.startParams.isEmpty)

        let phoneHarness = FlowTestHarness(
            loginResult: .success(
                .authRequired(
                    LoginResponse.AuthRequired(
                        authRequirements: AuthRequirements(
                            targetScore: 1,
                            operations: [
                                OperationRequirement(
                                    score: 1,
                                    type: .phoneNumberVerification,
                                    channels: [OperationChannel(channel: "+1******0400", id: "username-phone-channel")]
                                )
                            ]
                        )
                    )
                )
            ),
            loginIDCollectResult: .success(username)
        )
        phoneHarness.passkeyAttestation.availability = .unavailable("passkey creation unavailable")
        let phoneFlow = BoostLoginFlowImpl(
            ownIDOperation: phoneHarness.operation,
            userJourney: nil,
            sessionCreate: nil,
            coder: phoneHarness.coder,
            taskScope: phoneHarness.taskScope,
            context: nil,
            loginIDValidator: phoneHarness.validator,
            logger: nil
        )

        _ = await phoneFlow.start(.empty).whenSettled()
        let phoneParams = try requireRecordedValue(
            phoneHarness.phoneVerification.startParams,
            "Expected username phone verification start params"
        )

        #expect(phoneParams.loginID == username)
        #expect(phoneParams.loginIDHintID == "username-phone-channel")
        #expect(phoneHarness.emailVerification.startParams.isEmpty)
    }

    @Test func `Boost create passkey preserves registration fallback when attestation fails`() async throws {
        let loginID = FlowFixtures.loginID("fallback-registration@example.com")
        let harness = FlowTestHarness(
            loginResult: .success(.accountNotFound(LoginResponse.AccountNotFound())),
            loginIDCollectResult: .success(loginID),
            passkeyAttestationResult: .failure(
                .unexpected(errorCode: .unknown, message: "local attestation failed")
            )
        )
        let flow = BoostCreatePasskeyFlowImpl(
            ownIDOperation: harness.operation,
            boostLoginFlow: FlowBoostLoginFlowFake(
                result: .failure(.unexpected(message: "child login should not start"))
            ),
            userJourney: nil,
            sessionCreate: nil,
            coder: harness.coder,
            taskScope: harness.taskScope,
            context: nil,
            loginIDValidator: harness.validator,
            logger: nil
        )

        let response = try await requireSuccess(flow.start(.empty).whenSettled())

        let created = try requireCreatePasskeyOutcome(response)
        #expect(created.loginID == loginID)
        #expect(created.proofToken == nil)
        #expect(created.ownIdData == nil)
        let attestationParams = try requireRecordedValue(
            harness.passkeyAttestation.startParams,
            "Expected registration fallback attestation start params"
        )
        #expect(attestationParams.loginID == loginID)
    }
}

struct LoginIDOrderingCase: Sendable, CustomTestStringConvertible {
    let name: String
    let flowContext: @Sendable () -> BoostFlowContext
    let currentContext: Context?
    let lastUser: User?
    let expectedLoginID: LoginID?
    let expectedRawLoginID: String?
    let expectedLastUserReads: Int

    var testDescription: String { name }
}

struct SessionProviderCase: Sendable, CustomTestStringConvertible {
    let available: Bool
    let expectedSession: String?
    let expectedCreateCalls: Int

    var testDescription: String {
        available ? "session provider available" : "session provider unavailable"
    }
}
