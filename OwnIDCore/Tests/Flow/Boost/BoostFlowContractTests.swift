import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

// Covers: FLOW-010, FLOW-020, FLOW-030, FLOW-040, FLOW-120, FLOW-130, FLOW-140, FLOW-150, FLOW-170, FLOW-180, FLOW-200
struct BoostFlowContractTests {

    @Test func `Boost context and result descriptions redact sensitive values`() {
        let secret = "1234567890ABCDEFGHIJ"
        let traceParent = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00"
        let authChannel = "auth-user@example.test"
        var context = BoostFlowContext()
        context.loginID(secret)
        context.accessToken = AccessToken(token: secret)
        context.proofToken = ProofToken(token: secret)
        context.ownIdData = secret
        context.sessionPayload = secret
        context.ignoreLastUser = true
        context.allowedAuthOperations = [.emailVerification]
        context.source = .widgetButton
        context.traceParent = traceParent
        context.authMethod = .otp
        context.authRequiredResponse = LoginResponse.AuthRequired(
            authRequirements: AuthRequirements(
                targetScore: 10,
                operations: [
                    OperationRequirement(
                        score: 7,
                        type: .emailVerification,
                        channels: [OperationChannel(channel: authChannel, id: "email-main")]
                    ),
                    OperationRequirement(score: 3, type: .passkeyAuth, channels: nil),
                ]
            ),
            reason: "additional-auth"
        )
        context.requestedOps = [.emailVerification: true, .passkeyAuth: false]

        let contextDescription = context.description
        let expectedContextFragments = [
            "rawLoginID=12345678..[4]...CDEFGHIJ",
            "accessToken=AccessToken(token: 12345678..[4]...CDEFGHIJ)",
            "proofToken=ProofToken(token: 12345678..[4]...CDEFGHIJ)",
            "ownIdData=12345678..[4]...CDEFGHIJ",
            "sessionPayload=12345678..[4]...CDEFGHIJ",
            "ignoreLastUser=true",
            "allowedAuthOperations=",
            "BoostLoginAuthOperation.emailVerification",
            "source=widgetButton",
            "traceParent=\(traceParent)",
            "authMethod=otp",
            "authRequiredResponse=AuthRequired(AuthRequirements(targetScore=10",
            "EmailVerification(score=7, channels=[OperationChannel(channel: '*', id: 'email-main')])",
            "PasskeyAuth(score=3, channels=[nil])",
            "reason=additional-auth)",
            "requestedOps=",
            "OperationType.emailVerification: true",
            "OperationType.passkeyAuth: false",
        ]

        expectDescription(
            contextDescription,
            prefix: "FlowContext(",
            contains: expectedContextFragments,
            excludes: [secret, authChannel]
        )

        var contextWithEmptyAllowList = BoostFlowContext()
        contextWithEmptyAllowList.allowedAuthOperations = []
        #expect(!contextWithEmptyAllowList.description.contains("allowedAuthOperations"))

        let loginResponse = BoostFlowLoginResponse(
            loginID: LoginID(id: "person@example.test", type: .email),
            authMethod: .otp,
            accessToken: AccessToken(token: secret),
            sessionPayload: #"{"session":"secret"}"#,
            session: "host-session"
        )
        let createPasskeyResponse = BoostFlowCreatePasskeyResponse(
            loginID: LoginID(id: "person@example.test", type: .email),
            proofToken: ProofToken(token: secret),
            ownIdData: #"{"own":"secret"}"#
        )

        #expect(
            loginResponse.description
                == "Login(loginID: LoginID(id: 'p****n@example.test', type: email), authMethod: otp, accessToken: AccessToken(token: 12345678..[4]...CDEFGHIJ), sessionPayload='*', session='*')"
        )
        #expect(
            createPasskeyResponse.description
                == "CreatePasskey(loginID: LoginID(id: 'p****n@example.test', type: email), proofToken: Optional(ProofToken(token: 12345678..[4]...CDEFGHIJ)), ownIdData='*')"
        )
    }

    @Test func `Boost create-passkey ownIdData helper returns data only for matching current login ID`() {
        let response = BoostFlowCreatePasskeyResponse(
            loginID: LoginID(id: "person@example.com", type: .email),
            proofToken: ProofToken(token: "proof-token"),
            ownIdData: #"{"own":"data"}"#
        )

        #expect(response.ownIdData(forLoginID: "person@example.com") == #"{"own":"data"}"#)
        #expect(response.ownIdData(forLoginID: "  person@example.com\n") == #"{"own":"data"}"#)
        #expect(response.ownIdData(forLoginID: nil) == nil)
        #expect(response.ownIdData(forLoginID: "") == nil)
        #expect(response.ownIdData(forLoginID: "   \n\t") == nil)
        #expect(response.ownIdData(forLoginID: "other@example.com") == nil)

        let responseWithoutOwnIdData = BoostFlowCreatePasskeyResponse(
            loginID: LoginID(id: "person@example.com", type: .email),
            ownIdData: nil
        )

        #expect(responseWithoutOwnIdData.ownIdData(forLoginID: "person@example.com") == nil)
    }

    @Test func `Boost failure descriptions keep stable error category and message`() {
        #expect(
            BoostLoginFlowFailure.input(
                .unresolvedLoginID(errorCode: .invalidArgument, message: "bad login ID")
            ).description == "Input.UnresolvedLoginID(errorCode=invalid_argument, message=bad login ID)"
        )
        #expect(
            BoostLoginFlowFailure.account(
                .blocked(errorCode: .userBlocked, message: "blocked")
            ).description == "Account.Blocked(errorCode=user_blocked, message=blocked)"
        )
        #expect(
            BoostLoginFlowFailure.account(
                .notFound(errorCode: .userNotFound, message: "missing")
            ).description == "Account.NotFound(errorCode=user_not_found, message=missing)"
        )
        #expect(
            BoostLoginFlowFailure.insufficientAuth(
                errorCode: .unknown,
                message: "no operation"
            ).description == "InsufficientAuth(errorCode=unknown, message=no operation)"
        )
        #expect(
            BoostLoginFlowFailure.sessionCreationFailed(
                errorCode: .integrationError,
                message: "session rejected"
            ).description == "SessionCreationFailed(errorCode=integration_error, message=session rejected)"
        )
        #expect(
            BoostLoginFlowFailure.operationFailed(
                operationType: .passkeyAuth,
                errorCode: .passkeysNotSupported,
                message: "unavailable"
            ).description == "OperationFailed(errorCode=passkeys_not_supported, message=unavailable)"
        )
        #expect(
            BoostLoginFlowFailure.unexpected(
                errorCode: .unknown,
                message: "invariant"
            ).description == "Unexpected(errorCode=unknown, message=invariant)"
        )

        #expect(
            BoostCreatePasskeyFlowFailure.input(
                .unresolvedLoginID(errorCode: .invalidArgument, message: "bad login ID")
            ).description == "Input.UnresolvedLoginID(errorCode=invalid_argument, message=bad login ID)"
        )
        #expect(
            BoostCreatePasskeyFlowFailure.account(
                .blocked(errorCode: .userBlocked, message: "blocked")
            ).description == "Account.Blocked(errorCode=user_blocked, message=blocked)"
        )
        #expect(
            BoostCreatePasskeyFlowFailure.account(
                .notFound(errorCode: .userNotFound, message: "missing")
            ).description == "Account.NotFound(errorCode=user_not_found, message=missing)"
        )
        #expect(
            BoostCreatePasskeyFlowFailure.insufficientAuth(
                errorCode: .unknown,
                message: "no operation"
            ).description == "InsufficientAuth(errorCode=unknown, message=no operation)"
        )
        #expect(
            BoostCreatePasskeyFlowFailure.sessionCreationFailed(
                errorCode: .integrationError,
                message: "session rejected"
            ).description == "SessionCreationFailed(errorCode=integration_error, message=session rejected)"
        )
        #expect(
            BoostCreatePasskeyFlowFailure.operationFailed(
                operationType: .passkeyCreation,
                errorCode: .passkeyNotCreated,
                message: "creation failed"
            ).description == "OperationFailed(errorCode=passkey_not_created, message=creation failed)"
        )
        #expect(
            BoostCreatePasskeyFlowFailure.unexpected(
                errorCode: .unknown,
                message: "invariant"
            ).description == "Unexpected(errorCode=unknown, message=invariant)"
        )
    }

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

    @Test func `Boost flows fail when required login ID collection operation is unavailable`() async throws {
        let loginHarness = FlowTestHarness(loginResult: .success(FlowFixtures.loginSuccess()))
        loginHarness.container.remove((any LoginIDCollectOperation).self)
        let loginFlow = makeBoostLoginFlow(harness: loginHarness)

        let loginFailure = try await requireFailure(loginFlow.start(.empty).whenSettled())
        _ = try requireLoginOperationFailure(loginFailure, operationType: .loginIDCollect)

        #expect(loginHarness.loginIDCollect.availabilityParams.isEmpty)
        #expect(loginHarness.loginIDCollect.startParams.isEmpty)
        #expect(loginHarness.login.startParams.isEmpty)

        let createHarness = FlowTestHarness(loginResult: .success(FlowFixtures.loginSuccess()))
        createHarness.container.remove((any LoginIDCollectOperation).self)
        let createFlow = makeBoostCreatePasskeyFlow(harness: createHarness)

        let createFailure = try await requireFailure(createFlow.start(.empty).whenSettled())
        _ = try requireCreatePasskeyOperationFailure(createFailure, operationType: .loginIDCollect)

        #expect(createHarness.loginIDCollect.availabilityParams.isEmpty)
        #expect(createHarness.loginIDCollect.startParams.isEmpty)
        #expect(createHarness.login.startParams.isEmpty)
        #expect(createHarness.passkeyAttestation.startParams.isEmpty)
    }

    @Test func `Boost flows fail when required pre-auth login operation is unavailable`() async throws {
        let loginID = FlowFixtures.loginID("missing-login-operation@example.com")
        let loginHarness = FlowTestHarness(
            loginResult: .success(FlowFixtures.loginSuccess(id: loginID.id)),
            loginIDCollectResult: .success(loginID)
        )
        loginHarness.container.remove((any LoginOperation).self)
        let loginFlow = makeBoostLoginFlow(harness: loginHarness)

        let loginFailure = try await requireFailure(loginFlow.start(.empty).whenSettled())
        _ = try requireLoginOperationFailure(loginFailure, operationType: .sessionCreation)

        #expect(loginHarness.loginIDCollect.startParams.count == 1)
        #expect(loginHarness.login.startParams.isEmpty)

        let createHarness = FlowTestHarness(
            loginResult: .success(FlowFixtures.loginSuccess(id: loginID.id)),
            loginIDCollectResult: .success(loginID)
        )
        createHarness.container.remove((any LoginOperation).self)
        let createFlow = makeBoostCreatePasskeyFlow(harness: createHarness)

        let createFailure = try await requireFailure(createFlow.start(.empty).whenSettled())
        _ = try requireCreatePasskeyOperationFailure(createFailure, operationType: .sessionCreation)

        #expect(createHarness.loginIDCollect.startParams.count == 1)
        #expect(createHarness.login.startParams.isEmpty)
        #expect(createHarness.passkeyAttestation.startParams.isEmpty)
    }

    @Test func `Boost login maps session create provider failure to terminal integration failure`() async throws {
        let loginID = FlowFixtures.loginID("session-failure@example.com")
        let accessToken = FlowFixtures.accessToken(id: loginID.id)
        let sessionPayload = #"{"session":"failure"}"#
        let providerFailure = SessionCreateProviderFailure.rejected
        let harness = FlowTestHarness(
            loginResult: .success(
                .success(LoginResponse.Success(accessToken: accessToken, sessionPayload: sessionPayload))
            ),
            loginIDCollectResult: .success(loginID)
        )
        let sessionCreate = FlowSessionCreateFake(createResult: .failure(providerFailure))
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

        let failure = try await requireFailure(flow.start().whenSettled())
        let underlyingError = try requireLoginSessionCreationFailure(failure)

        #expect(underlyingError as? SessionCreateProviderFailure == providerFailure)
        #expect(sessionCreate.createParams.count == 1)
    }

    @Test func `Boost login maps session create cancellation to terminal system cancellation`() async throws {
        let loginID = FlowFixtures.loginID("session-canceled@example.com")
        let accessToken = FlowFixtures.accessToken(id: loginID.id)
        let harness = FlowTestHarness(
            loginResult: .success(
                .success(LoginResponse.Success(accessToken: accessToken, sessionPayload: #"{"session":"canceled"}"#))
            ),
            loginIDCollectResult: .success(loginID)
        )
        let sessionCreate = FlowSessionCreateFake(createResult: .failure(CancellationError()))
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

        let reason = try await requireCancellation(flow.start().whenSettled())

        try requireSystemCancellation(reason)
        #expect(sessionCreate.createParams.count == 1)
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

    @Test func `Boost create passkey maps existing-account session create failure to terminal integration failure`() async throws {
        let loginID = FlowFixtures.loginID("existing-failure@example.com")
        let accessToken = FlowFixtures.accessToken(id: loginID.id)
        let providerFailure = SessionCreateProviderFailure.rejected
        let harness = FlowTestHarness(
            loginResult: .success(
                .success(LoginResponse.Success(accessToken: accessToken, sessionPayload: "existing-failure-payload"))
            ),
            loginIDCollectResult: .success(loginID)
        )
        let sessionCreate = FlowSessionCreateFake(createResult: .failure(providerFailure))
        let flow = BoostCreatePasskeyFlowImpl(
            ownIDOperation: harness.operation,
            boostLoginFlow: FlowBoostLoginFlowFake(
                result: .failure(.unexpected(message: "child login should not start"))
            ),
            userJourney: nil,
            sessionCreate: sessionCreate,
            coder: harness.coder,
            taskScope: harness.taskScope,
            context: nil,
            loginIDValidator: harness.validator,
            logger: nil
        )

        let failure = try await requireFailure(flow.start(.empty).whenSettled())
        let underlyingError = try requireCreatePasskeySessionCreationFailure(failure)

        #expect(underlyingError as? SessionCreateProviderFailure == providerFailure)
        #expect(sessionCreate.createParams.count == 1)
        #expect(harness.passkeyAttestation.startParams.isEmpty)
    }

    @Test func `Boost create passkey maps existing-account session create cancellation to terminal system cancellation`() async throws {
        let loginID = FlowFixtures.loginID("existing-canceled@example.com")
        let accessToken = FlowFixtures.accessToken(id: loginID.id)
        let harness = FlowTestHarness(
            loginResult: .success(
                .success(LoginResponse.Success(accessToken: accessToken, sessionPayload: "existing-canceled-payload"))
            ),
            loginIDCollectResult: .success(loginID)
        )
        let sessionCreate = FlowSessionCreateFake(createResult: .failure(CancellationError()))
        let flow = BoostCreatePasskeyFlowImpl(
            ownIDOperation: harness.operation,
            boostLoginFlow: FlowBoostLoginFlowFake(
                result: .failure(.unexpected(message: "child login should not start"))
            ),
            userJourney: nil,
            sessionCreate: sessionCreate,
            coder: harness.coder,
            taskScope: harness.taskScope,
            context: nil,
            loginIDValidator: harness.validator,
            logger: nil
        )

        let reason = try await requireCancellation(flow.start(.empty).whenSettled())

        try requireSystemCancellation(reason)
        #expect(sessionCreate.createParams.count == 1)
        #expect(harness.passkeyAttestation.startParams.isEmpty)
    }

    @Test func `Boost flows propagate login ID collect cancellation reason`() async throws {
        let expectedReason = Reason.userClose(details: "login ID dismissed")
        let loginHarness = FlowTestHarness(
            loginResult: .success(FlowFixtures.loginSuccess()),
            loginIDCollectResult: .canceled(expectedReason)
        )
        let loginFlow = makeBoostLoginFlow(harness: loginHarness)

        let loginReason = try await requireCancellation(loginFlow.start(.empty).whenSettled())

        try requireSameReason(loginReason, expectedReason)
        #expect(loginHarness.loginIDCollect.startParams.count == 1)
        #expect(loginHarness.login.startParams.isEmpty)

        let createHarness = FlowTestHarness(
            loginResult: .success(FlowFixtures.loginSuccess()),
            loginIDCollectResult: .canceled(expectedReason)
        )
        let createFlow = makeBoostCreatePasskeyFlow(harness: createHarness)

        let createReason = try await requireCancellation(createFlow.start(.empty).whenSettled())

        try requireSameReason(createReason, expectedReason)
        #expect(createHarness.loginIDCollect.startParams.count == 1)
        #expect(createHarness.login.startParams.isEmpty)
        #expect(createHarness.passkeyAttestation.startParams.isEmpty)
    }

    @Test func `Boost flows map login ID collect failure to terminal operation failure`() async throws {
        let collectFailure = LoginIDCollectOperationFailure.integration(
            .ui(errorCode: .integrationError, message: "collect UI failed")
        )
        let loginHarness = FlowTestHarness(
            loginResult: .success(FlowFixtures.loginSuccess()),
            loginIDCollectResult: .failure(collectFailure)
        )
        let loginFlow = makeBoostLoginFlow(harness: loginHarness)

        let loginFailure = try await requireFailure(loginFlow.start(.empty).whenSettled())
        let loginOperationFailure = try requireLoginOperationFailure(loginFailure, operationType: .loginIDCollect).failure

        try requireLoginIDCollectFailure(loginOperationFailure, expectedMessage: collectFailure.message)
        #expect(loginHarness.loginIDCollect.startParams.count == 1)
        #expect(loginHarness.login.startParams.isEmpty)

        let createHarness = FlowTestHarness(
            loginResult: .success(FlowFixtures.loginSuccess()),
            loginIDCollectResult: .failure(collectFailure)
        )
        let createFlow = makeBoostCreatePasskeyFlow(harness: createHarness)

        let createFailure = try await requireFailure(createFlow.start(.empty).whenSettled())
        let createOperationFailure = try requireCreatePasskeyOperationFailure(
            createFailure,
            operationType: .loginIDCollect
        ).failure

        try requireLoginIDCollectFailure(createOperationFailure, expectedMessage: collectFailure.message)
        #expect(createHarness.loginIDCollect.startParams.count == 1)
        #expect(createHarness.login.startParams.isEmpty)
        #expect(createHarness.passkeyAttestation.startParams.isEmpty)
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

    @Test(
        arguments: [
            AllowedAuthDefaultCase(name: "allow-list absent", context: .empty),
            AllowedAuthDefaultCase(
                name: "allow-list explicitly empty",
                context: BoostFlowContext { $0.allowedAuthOperations = [] }
            ),
        ]
    )
    func `Boost login absent or empty authentication allow-list preserves default selection`(
        _ testCase: AllowedAuthDefaultCase
    ) async throws {
        let loginID = FlowFixtures.loginID("default-auth-selection", type: .userName)
        let harness = FlowTestHarness(
            loginResult: .success(
                authRequiredLoginResponse(
                    operations: [
                        authRequirement(.emailVerification, channelID: "default-email-channel"),
                        authRequirement(.phoneNumberVerification, channelID: "default-phone-channel"),
                        authRequirement(.passkeyAuth),
                    ]
                )
            ),
            additionalLoginResults: [.success(FlowFixtures.loginSuccess(id: loginID.id, type: .userName))],
            loginIDCollectResult: .success(loginID)
        )
        let flow = makeBoostLoginFlow(harness: harness)

        _ = try await requireSuccess(flow.start(testCase.context).whenSettled())

        #expect(harness.emailVerification.startParams.count == 1, "\(testCase.name)")
        #expect(harness.phoneVerification.startParams.isEmpty, "\(testCase.name)")
        #expect(harness.passkeyAssertion.startParams.isEmpty, "\(testCase.name)")
        #expect(harness.passkeyAttestation.startParams.isEmpty, "\(testCase.name)")
    }

    @Test func `Boost login authentication allow-list starts only permitted verification`() async throws {
        let loginID = FlowFixtures.loginID("verification-allow-list", type: .userName)
        let emailHarness = FlowTestHarness(
            loginResult: .success(
                authRequiredLoginResponse(
                    operations: [
                        authRequirement(.phoneNumberVerification, channelID: "excluded-phone-channel"),
                        authRequirement(.passkeyAuth),
                        authRequirement(.emailVerification, channelID: "allowed-email-channel"),
                    ]
                )
            ),
            additionalLoginResults: [.success(FlowFixtures.loginSuccess(id: loginID.id, type: .userName))],
            loginIDCollectResult: .success(loginID)
        )
        let emailFlow = makeBoostLoginFlow(harness: emailHarness)
        let emailContext = BoostFlowContext { $0.allowedAuthOperations = [.emailVerification] }

        _ = try await requireSuccess(emailFlow.start(emailContext).whenSettled())

        let emailParams = try requireRecordedValue(
            emailHarness.emailVerification.startParams,
            "Expected allowed email verification start params"
        )
        #expect(emailParams.loginIDHintID == "allowed-email-channel")
        #expect(emailHarness.phoneVerification.startParams.isEmpty)
        #expect(emailHarness.passkeyAssertion.startParams.isEmpty)
        #expect(emailHarness.passkeyAttestation.startParams.isEmpty)

        let phoneHarness = FlowTestHarness(
            loginResult: .success(
                authRequiredLoginResponse(
                    operations: [
                        authRequirement(.emailVerification, channelID: "excluded-email-channel"),
                        authRequirement(.passkeyAuth),
                        authRequirement(.phoneNumberVerification, channelID: "allowed-phone-channel"),
                    ]
                )
            ),
            additionalLoginResults: [.success(FlowFixtures.loginSuccess(id: loginID.id, type: .userName))],
            loginIDCollectResult: .success(loginID)
        )
        let phoneFlow = makeBoostLoginFlow(harness: phoneHarness)
        let phoneContext = BoostFlowContext { $0.allowedAuthOperations = [.phoneNumberVerification] }

        _ = try await requireSuccess(phoneFlow.start(phoneContext).whenSettled())

        let phoneParams = try requireRecordedValue(
            phoneHarness.phoneVerification.startParams,
            "Expected allowed phone verification start params"
        )
        #expect(phoneParams.loginIDHintID == "allowed-phone-channel")
        #expect(phoneHarness.emailVerification.startParams.isEmpty)
        #expect(phoneHarness.passkeyAssertion.startParams.isEmpty)
        #expect(phoneHarness.passkeyAttestation.startParams.isEmpty)
    }

    @Test func `Boost login passkey allow-list permits authentication and creation fallback`() async throws {
        let loginID = FlowFixtures.loginID("passkey-allow-list", type: .userName)
        let authHarness = FlowTestHarness(
            loginResult: .success(
                authRequiredLoginResponse(
                    operations: [
                        authRequirement(.passkeyAuth),
                        authRequirement(.emailVerification, channelID: "excluded-email-channel"),
                    ]
                )
            ),
            additionalLoginResults: [.success(FlowFixtures.loginSuccess(id: loginID.id, type: .userName))],
            loginIDCollectResult: .success(loginID),
            passkeyAssertionResult: .success(FlowFixtures.accessToken(id: loginID.id, type: .userName))
        )
        let authFlow = makeBoostLoginFlow(harness: authHarness)
        let context = BoostFlowContext { $0.allowedAuthOperations = [.passkey] }

        _ = try await requireSuccess(authFlow.start(context).whenSettled())

        #expect(authHarness.passkeyAssertion.startParams.count == 1)
        #expect(authHarness.passkeyAttestation.startParams.isEmpty)
        #expect(authHarness.emailVerification.startParams.isEmpty)
        #expect(authHarness.phoneVerification.startParams.isEmpty)

        let creationHarness = FlowTestHarness(
            loginResult: .success(
                authRequiredLoginResponse(
                    operations: [authRequirement(.emailVerification, channelID: "excluded-fallback-email-channel")]
                )
            ),
            loginIDCollectResult: .success(loginID)
        )
        let creationFlow = makeBoostLoginFlow(harness: creationHarness)

        let failure = try await requireFailure(creationFlow.start(context).whenSettled())

        try requireLoginInsufficientAuthFailure(failure, expectedMessageFragment: nil)
        #expect(creationHarness.passkeyAttestation.startParams.count == 1)
        #expect(creationHarness.passkeyAssertion.startParams.isEmpty)
        #expect(creationHarness.emailVerification.startParams.isEmpty)
        #expect(creationHarness.phoneVerification.startParams.isEmpty)
    }

    @Test func `Boost login unmatched authentication allow-list fails without starting excluded operations`() async throws {
        let loginID = FlowFixtures.loginID("unmatched-allow-list", type: .userName)
        let harness = FlowTestHarness(
            loginResult: .success(
                authRequiredLoginResponse(
                    operations: [authRequirement(.phoneNumberVerification, channelID: "excluded-phone-channel")]
                )
            ),
            loginIDCollectResult: .success(loginID)
        )
        let flow = makeBoostLoginFlow(harness: harness)
        let context = BoostFlowContext { $0.allowedAuthOperations = [.emailVerification] }

        let failure = try await requireFailure(flow.start(context).whenSettled())

        try requireLoginInsufficientAuthFailure(failure, expectedMessageFragment: nil)
        #expect(harness.emailVerification.startParams.isEmpty)
        #expect(harness.phoneVerification.startParams.isEmpty)
        #expect(harness.passkeyAssertion.startParams.isEmpty)
        #expect(harness.passkeyAttestation.startParams.isEmpty)
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

    @Test func `Boost login auth-required typed login mismatch fails without starting mismatched verification`() async throws {
        let loginID = FlowFixtures.loginID("typed-email@example.test", type: .email)
        let harness = FlowTestHarness(
            loginResult: .success(
                .authRequired(
                    LoginResponse.AuthRequired(
                        authRequirements: AuthRequirements(
                            targetScore: 1,
                            operations: [
                                OperationRequirement(
                                    score: 1,
                                    type: .phoneNumberVerification,
                                    channels: [OperationChannel(channel: "+1******0600", id: "mismatched-phone-channel")]
                                )
                            ]
                        )
                    )
                )
            ),
            loginIDCollectResult: .success(loginID)
        )
        harness.passkeyAttestation.availability = .unavailable("passkey creation unavailable")
        let flow = makeBoostLoginFlow(harness: harness)

        let failure = try await requireFailure(flow.start(.empty).whenSettled())

        try requireLoginInsufficientAuthFailure(failure)
        #expect(harness.loginIDCollect.startParams.count == 1)
        #expect(harness.login.startParams.count == 1)
        #expect(harness.passkeyAttestation.startParams.isEmpty)
        #expect(harness.phoneVerification.startParams.isEmpty)
    }

    @Test func `Boost login success without resolved login ID fails as unexpected invariant violation`() async throws {
        var context = BoostFlowContext()
        context.authRequiredResponse = LoginResponse.AuthRequired(
            authRequirements: AuthRequirements(
                targetScore: 1,
                operations: [
                    OperationRequirement(
                        score: 1,
                        type: .emailVerification,
                        channels: [OperationChannel(channel: "verified@example.test", id: "verified-email-channel")]
                    )
                ]
            )
        )
        let harness = FlowTestHarness(
            loginResult: .success(FlowFixtures.loginSuccess(id: "verified@example.test")),
            emailVerificationResult: .success(
                .accessToken(FlowFixtures.accessToken(id: "verified@example.test"))
            )
        )
        harness.passkeyAttestation.availability = .unavailable("passkey creation unavailable")
        let flow = makeBoostLoginFlow(harness: harness)

        let failure = try await requireFailure(flow.start(context).whenSettled())

        try requireLoginUnexpectedFailure(
            failure,
            expectedMessage: "Missing required loginID in login success context"
        )
        #expect(harness.emailVerification.startParams.count == 1)
        #expect(harness.login.startParams.count == 1)
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

struct AllowedAuthDefaultCase: Sendable, CustomTestStringConvertible {
    let name: String
    let context: BoostFlowContext

    var testDescription: String { name }
}

private enum SessionCreateProviderFailure: Error, Sendable, Equatable {
    case rejected
}

private func authRequiredLoginResponse(operations: [OperationRequirement]) -> LoginResponse {
    .authRequired(
        LoginResponse.AuthRequired(
            authRequirements: AuthRequirements(targetScore: 1, operations: operations)
        )
    )
}

private func authRequirement(
    _ type: OperationType,
    channelID: String? = nil
) -> OperationRequirement {
    OperationRequirement(
        score: 1,
        type: type,
        channels: channelID.map { [OperationChannel(channel: "masked", id: $0)] }
    )
}

private func expectDescription(
    _ description: String,
    prefix: String,
    contains expectedFragments: [String],
    excludes excludedFragments: [String],
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) {
    #expect(description.hasPrefix(prefix), sourceLocation: sourceLocation)
    #expect(description.hasSuffix(")"), sourceLocation: sourceLocation)
    for fragment in expectedFragments {
        #expect(description.contains(fragment), "Missing \(fragment) in \(description)", sourceLocation: sourceLocation)
    }
    for fragment in excludedFragments {
        #expect(!description.contains(fragment), "Unexpected \(fragment) in \(description)", sourceLocation: sourceLocation)
    }
}

private func makeBoostLoginFlow(
    harness: FlowTestHarness,
    userRepository: (any UserRepository)? = nil,
    sessionCreate: (any SessionCreate)? = nil,
    context: Context? = nil
) -> BoostLoginFlowImpl {
    BoostLoginFlowImpl(
        userRepository: userRepository,
        ownIDOperation: harness.operation,
        userJourney: nil,
        sessionCreate: sessionCreate,
        coder: harness.coder,
        taskScope: harness.taskScope,
        context: context,
        loginIDValidator: harness.validator,
        logger: nil
    )
}

private func makeBoostCreatePasskeyFlow(
    harness: FlowTestHarness,
    userRepository: (any UserRepository)? = nil,
    boostLoginFlow: (any BoostLoginFlow)? = nil,
    sessionCreate: (any SessionCreate)? = nil,
    context: Context? = nil
) -> BoostCreatePasskeyFlowImpl {
    BoostCreatePasskeyFlowImpl(
        userRepository: userRepository,
        ownIDOperation: harness.operation,
        boostLoginFlow: boostLoginFlow
            ?? FlowBoostLoginFlowFake(
                result: .failure(.unexpected(message: "child login should not start"))
            ),
        userJourney: nil,
        sessionCreate: sessionCreate,
        coder: harness.coder,
        taskScope: harness.taskScope,
        context: context,
        loginIDValidator: harness.validator,
        logger: nil
    )
}

private func requireLoginOperationFailure(
    _ failure: BoostLoginFlowFailure,
    operationType: OperationType,
    expectedErrorCode: ErrorCode = .integrationError,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws -> (operationID: OperationID?, failure: (any OperationFailure)?) {
    switch failure {
    case .operationFailed(let actualOperationType, let errorCode, let message, let operationID, let operationFailure, _):
        #expect(actualOperationType == operationType, sourceLocation: sourceLocation)
        #expect(errorCode == expectedErrorCode, sourceLocation: sourceLocation)
        #expect(message.isEmpty == false, sourceLocation: sourceLocation)
        return (operationID, operationFailure)
    default:
        return try #require(
            nil as (operationID: OperationID?, failure: (any OperationFailure)?)?,
            "Expected operation failure for \(operationType), got \(failure)",
            sourceLocation: sourceLocation
        )
    }
}

private func requireCreatePasskeyOperationFailure(
    _ failure: BoostCreatePasskeyFlowFailure,
    operationType: OperationType,
    expectedErrorCode: ErrorCode = .integrationError,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws -> (operationID: OperationID?, failure: (any OperationFailure)?) {
    switch failure {
    case .operationFailed(let actualOperationType, let errorCode, let message, let operationID, let operationFailure, _):
        #expect(actualOperationType == operationType, sourceLocation: sourceLocation)
        #expect(errorCode == expectedErrorCode, sourceLocation: sourceLocation)
        #expect(message.isEmpty == false, sourceLocation: sourceLocation)
        return (operationID, operationFailure)
    default:
        return try #require(
            nil as (operationID: OperationID?, failure: (any OperationFailure)?)?,
            "Expected operation failure for \(operationType), got \(failure)",
            sourceLocation: sourceLocation
        )
    }
}

private func requireLoginIDCollectFailure(
    _ failure: (any OperationFailure)?,
    expectedMessage: String,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws {
    let collectFailure = try #require(
        failure as? LoginIDCollectOperationFailure,
        "Expected login ID collect operation failure",
        sourceLocation: sourceLocation
    )
    #expect(collectFailure.errorCode == .integrationError, sourceLocation: sourceLocation)
    #expect(collectFailure.message == expectedMessage, sourceLocation: sourceLocation)
}

private func requireLoginInsufficientAuthFailure(
    _ failure: BoostLoginFlowFailure,
    expectedMessageFragment: String? = "No operation available",
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws {
    switch failure {
    case .insufficientAuth(let errorCode, let message):
        #expect(errorCode == .unknown, sourceLocation: sourceLocation)
        if let expectedMessageFragment {
            #expect(message.contains(expectedMessageFragment), sourceLocation: sourceLocation)
        } else {
            #expect(!message.isEmpty, sourceLocation: sourceLocation)
        }
    default:
        _ = try #require(nil as Void?, "Expected insufficient auth, got \(failure)", sourceLocation: sourceLocation)
    }
}

private func requireLoginUnexpectedFailure(
    _ failure: BoostLoginFlowFailure,
    expectedMessage: String,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws {
    switch failure {
    case .unexpected(let errorCode, let message, _):
        #expect(errorCode == .unknown, sourceLocation: sourceLocation)
        #expect(message == expectedMessage, sourceLocation: sourceLocation)
    default:
        _ = try #require(nil as Void?, "Expected unexpected failure, got \(failure)", sourceLocation: sourceLocation)
    }
}

private func requireSameReason(
    _ actual: Reason,
    _ expected: Reason,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws {
    switch (actual, expected) {
    case (.timeout, .timeout),
        (.moveToOtherChallenge, .moveToOtherChallenge),
        (.alreadyExists, .alreadyExists):
        return
    case (.userClose(let actualDetails), .userClose(let expectedDetails)),
        (.systemError(let actualDetails), .systemError(let expectedDetails)),
        (.unknown(let actualDetails), .unknown(let expectedDetails)):
        #expect(actualDetails == expectedDetails, sourceLocation: sourceLocation)
    default:
        _ = try #require(
            nil as Void?,
            "Expected cancellation reason \(expected), got \(actual)",
            sourceLocation: sourceLocation
        )
    }
}

private func requireLoginSessionCreationFailure(
    _ failure: BoostLoginFlowFailure,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws -> any Error & Sendable {
    switch failure {
    case .sessionCreationFailed(let errorCode, _, let underlyingError):
        #expect(errorCode == .integrationError, sourceLocation: sourceLocation)
        return try #require(underlyingError, "Expected provider failure as underlying error", sourceLocation: sourceLocation)
    default:
        return try #require(
            nil as (any Error & Sendable)?,
            "Expected session creation failure, got \(failure)",
            sourceLocation: sourceLocation
        )
    }
}

private func requireCreatePasskeySessionCreationFailure(
    _ failure: BoostCreatePasskeyFlowFailure,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws -> any Error & Sendable {
    switch failure {
    case .sessionCreationFailed(let errorCode, _, let underlyingError):
        #expect(errorCode == .integrationError, sourceLocation: sourceLocation)
        return try #require(underlyingError, "Expected provider failure as underlying error", sourceLocation: sourceLocation)
    default:
        return try #require(
            nil as (any Error & Sendable)?,
            "Expected session creation failure, got \(failure)",
            sourceLocation: sourceLocation
        )
    }
}

private func requireSystemCancellation(
    _ reason: Reason,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws {
    guard case .systemError = reason else {
        _ = try #require(nil as Void?, "Expected system cancellation, got \(reason)", sourceLocation: sourceLocation)
        return
    }
}
