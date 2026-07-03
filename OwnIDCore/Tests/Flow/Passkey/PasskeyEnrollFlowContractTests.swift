import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

// Covers: FLOW-050, FLOW-060, FLOW-070, FLOW-160, FLOW-190, FLOW-ORCH-040
struct PasskeyEnrollFlowContractTests {

    @Test func `Passkey enroll context response and failure descriptions are stable and redacted`() {
        let secret = "1234567890ABCDEFGHIJ"
        let loginID = FlowFixtures.loginID("person@example.test")
        var context = PasskeyEnrollFlowContext()
        context.accessToken = AccessToken(token: secret)
        context.proofToken = ProofToken(token: secret)
        context.headless = true

        let contextDescription = context.description

        #expect(
            contextDescription
                == "PasskeyEnrollFlowContext(accessToken=AccessToken(token: 12345678..[4]...CDEFGHIJ), proofToken=ProofToken(token: 12345678..[4]...CDEFGHIJ), headless=true)"
        )
        #expect(!contextDescription.contains(secret))
        #expect(
            PasskeyEnrollFlowResponse(loginID: loginID).description
                == "PasskeyEnrollFlowResponse(loginID: LoginID(id: 'p****n@example.test', type: email))"
        )
        #expect(
            PasskeyEnrollFlowFailure.input(
                .missingAccessToken(errorCode: .invalidArgument, message: "AccessToken is required")
            ).description == "Input.MissingAccessToken(errorCode=invalid_argument, message=AccessToken is required)"
        )
        #expect(
            PasskeyEnrollFlowFailure.input(
                .unresolvedLoginID(errorCode: .loginIDValidationFailed, message: "invalid login ID")
            ).description == "Input.UnresolvedLoginID(errorCode=login_id_validation_failed, message=invalid login ID)"
        )
        #expect(
            PasskeyEnrollFlowFailure.operationFailed(
                operationType: .passkeyEnrollment,
                errorCode: .passkeyNotCreated,
                message: "enroll failed"
            ).description == "OperationFailed(errorCode=passkey_not_created, message=enroll failed)"
        )
        #expect(
            PasskeyEnrollFlowFailure.unexpected(
                errorCode: .unknown,
                message: "missing proof token"
            ).description == "Unexpected(errorCode=unknown, message=missing proof token)"
        )
    }

    @Test func `Passkey enroll reports missing access token without starting operations`() async throws {
        let harness = FlowTestHarness(loginResult: .success(FlowFixtures.loginSuccess()))
        let flow = makePasskeyEnrollFlow(harness: harness)

        let availability = await flow.availability(params: PasskeyEnrollFlowContext())
        let failure = try await requireFailure(flow.start(PasskeyEnrollFlowContext()).whenSettled())
        let message = try requireFlowUnavailable(availability)
        let (errorCode, failureMessage) = try requireMissingAccessToken(failure)

        #expect(message == "AccessToken is required")
        #expect(errorCode == .invalidArgument)
        #expect(failureMessage == "AccessToken is required")
        #expect(harness.passkeyAttestation.startParams.isEmpty)
        #expect(harness.passkeyEnroll.startParams.isEmpty)
    }

    @Test func `Passkey enroll uses proof token branch and preserves headless param`() async throws {
        let loginID = FlowFixtures.loginID("enroll@example.com")
        let accessToken = FlowFixtures.accessToken(id: loginID.id)
        let proofToken = ProofToken(token: "existing-proof")
        let harness = FlowTestHarness(loginResult: .success(FlowFixtures.loginSuccess()))
        let flow = makePasskeyEnrollFlow(harness: harness)
        var context = PasskeyEnrollFlowContext()
        context.accessToken = accessToken
        context.proofToken = proofToken
        context.headless = true

        let availability = await flow.availability(params: context)
        let response = try await requireSuccess(flow.start(context).whenSettled())
        let enrollAvailabilityParams = try requireRecordedValue(
            harness.passkeyEnroll.availabilityParams,
            "Expected proof-token enroll availability params"
        )
        let enrollStartParams = try requireRecordedValue(
            harness.passkeyEnroll.startParams,
            "Expected proof-token enroll start params"
        )

        try requireFlowAvailable(availability)
        #expect(response.loginID == loginID)
        #expect(harness.passkeyAttestation.availabilityParams.isEmpty)
        #expect(harness.passkeyAttestation.startParams.isEmpty)
        #expect(enrollAvailabilityParams.proofToken == proofToken)
        #expect(enrollAvailabilityParams.accessToken == accessToken)
        #expect(enrollAvailabilityParams.headless == true)
        #expect(enrollStartParams.proofToken == proofToken)
        #expect(enrollStartParams.accessToken == accessToken)
        #expect(enrollStartParams.headless == true)
    }

    @Test func `Passkey enroll success records headless UserJourney lifecycle without changing settlement`() async throws {
        let loginID = FlowFixtures.loginID("journey-success@example.com")
        let accessToken = FlowFixtures.accessToken(id: loginID.id)
        let proofToken = ProofToken(token: "journey-proof")
        let traceParent = Self.traceParent
        let userJourney = RecordingFlowUserJourney()
        let harness = FlowTestHarness(loginResult: .success(FlowFixtures.loginSuccess()))
        let flow = makePasskeyEnrollFlow(harness: harness, userJourney: userJourney)
        let context = makeHeadlessPasskeyEnrollContext(
            accessToken: accessToken,
            proofToken: proofToken,
            traceParent: traceParent
        )

        let response = try await requireSuccess(flow.start(context).whenSettled())
        let operationID = try #require(harness.passkeyEnroll.startedControllers.first?.operationID)

        #expect(response.loginID == loginID)
        try assertHeadlessPasskeyEnrollJourneyStarted(userJourney, traceParent: traceParent, loginID: loginID)
        #expect(userJourney.startedOperations.get() == [operationID])
        let completion = try requireOperationCompletion(userJourney.completedOperations.get(), operationID: operationID)
        #expect(completion.errorCode == nil)
        #expect(completion.source == nil)
        #expect(completion.message == nil)
        try requireCompletedJourneyOutcome(userJourney.completedOutcomes.get())
    }

    @Test func `Passkey enroll cancellation records headless UserJourney lifecycle without changing settlement`() async throws {
        let loginID = FlowFixtures.loginID("journey-cancel@example.com")
        let accessToken = FlowFixtures.accessToken(id: loginID.id)
        let proofToken = ProofToken(token: "journey-proof")
        let traceParent = Self.traceParent
        let reason = Reason.userClose(details: "enroll canceled")
        let userJourney = RecordingFlowUserJourney()
        let harness = FlowTestHarness(
            loginResult: .success(FlowFixtures.loginSuccess()),
            passkeyEnrollResult: .canceled(reason)
        )
        let flow = makePasskeyEnrollFlow(harness: harness, userJourney: userJourney)
        let context = makeHeadlessPasskeyEnrollContext(
            accessToken: accessToken,
            proofToken: proofToken,
            traceParent: traceParent
        )

        let settledReason = try await requireCancellation(flow.start(context).whenSettled())
        let operationID = try #require(harness.passkeyEnroll.startedControllers.first?.operationID)

        #expect(settledReason.description == reason.description)
        try assertHeadlessPasskeyEnrollJourneyStarted(userJourney, traceParent: traceParent, loginID: loginID)
        #expect(userJourney.startedOperations.get() == [operationID])
        let completion = try requireOperationCompletion(userJourney.completedOperations.get(), operationID: operationID)
        #expect(completion.errorCode == .aborted)
        #expect(completion.source == "PasskeyEnrollFlowActor.reduce.enrollResult.canceled")
        #expect(completion.message == "Canceled with reason: \(reason.description)")
        let outcome = try requireErrorJourneyOutcome(userJourney.completedOutcomes.get(), errorCode: .aborted)
        #expect(outcome.source == "PasskeyEnrollFlowImpl.handleStateChange.canceled")
        #expect(outcome.message == "Canceled with reason: \(reason.description)")
    }

    @Test func `Passkey enroll failure records headless UserJourney lifecycle without changing settlement`() async throws {
        let loginID = FlowFixtures.loginID("journey-failure@example.com")
        let accessToken = FlowFixtures.accessToken(id: loginID.id)
        let proofToken = ProofToken(token: "journey-proof")
        let traceParent = Self.traceParent
        let enrollFailure = PasskeyEnrollOperationFailure.access(
            .forbidden(errorCode: .forbidden, message: "Enroll forbidden")
        )
        let userJourney = RecordingFlowUserJourney()
        let harness = FlowTestHarness(
            loginResult: .success(FlowFixtures.loginSuccess()),
            passkeyEnrollResult: .failure(enrollFailure)
        )
        let flow = makePasskeyEnrollFlow(harness: harness, userJourney: userJourney)
        let context = makeHeadlessPasskeyEnrollContext(
            accessToken: accessToken,
            proofToken: proofToken,
            traceParent: traceParent
        )

        let failure = try await requireFailure(flow.start(context).whenSettled())
        let operationID = try #require(harness.passkeyEnroll.startedControllers.first?.operationID)

        #expect(failure.errorCode == enrollFailure.errorCode)
        try assertHeadlessPasskeyEnrollJourneyStarted(userJourney, traceParent: traceParent, loginID: loginID)
        #expect(userJourney.startedOperations.get() == [operationID])
        let completion = try requireOperationCompletion(userJourney.completedOperations.get(), operationID: operationID)
        #expect(completion.errorCode == enrollFailure.errorCode)
        #expect(completion.source == "PasskeyEnrollFlowActor.reduce.enrollResult.failure")
        #expect(completion.message == enrollFailure.message)
        let outcome = try requireErrorJourneyOutcome(userJourney.completedOutcomes.get(), errorCode: enrollFailure.errorCode)
        #expect(outcome.source == "PasskeyEnrollFlowImpl.handleStateChange.failure")
        #expect(outcome.message == failure.message)
    }

    @Test func `Passkey enroll runs local attestation before enroll when proof token is absent`() async throws {
        let loginID = FlowFixtures.loginID("attested@example.com")
        let accessToken = FlowFixtures.accessToken(id: loginID.id)
        let proofToken = ProofToken(token: "attested-proof")
        let harness = FlowTestHarness(
            loginResult: .success(FlowFixtures.loginSuccess()),
            passkeyAttestationResult: .success(
                FlowFixtures.attestationResponse(
                    proofToken: proofToken,
                    ownIdData: #"{"notReturned":true}"#
                )
            )
        )
        let flow = makePasskeyEnrollFlow(harness: harness)
        var context = PasskeyEnrollFlowContext()
        context.accessToken = accessToken
        context.headless = true

        let availability = await flow.availability(params: context)
        let enrollAvailabilityCountAfterPreflight = harness.passkeyEnroll.availabilityParams.count
        let response = try await requireSuccess(flow.start(context).whenSettled())
        let attestationAvailabilityParams = try requireRecordedValue(
            harness.passkeyAttestation.availabilityParams,
            "Expected attestation availability params"
        )
        let attestationStartParams = try requireRecordedValue(
            harness.passkeyAttestation.startParams,
            "Expected attestation start params"
        )
        let enrollAvailabilityParams = try requireRecordedValue(
            harness.passkeyEnroll.availabilityParams,
            "Expected attested enroll availability params"
        )
        let enrollStartParams = try requireRecordedValue(
            harness.passkeyEnroll.startParams,
            "Expected attested enroll start params"
        )

        try requireFlowAvailable(availability)
        #expect(response == PasskeyEnrollFlowResponse(loginID: loginID))
        #expect(enrollAvailabilityCountAfterPreflight == 0)
        #expect(attestationAvailabilityParams.accessToken == accessToken)
        #expect(attestationAvailabilityParams.loginID == nil)
        #expect(attestationStartParams.accessToken == accessToken)
        #expect(attestationStartParams.loginID == nil)
        #expect(enrollAvailabilityParams.proofToken == proofToken)
        #expect(enrollAvailabilityParams.accessToken == accessToken)
        #expect(enrollAvailabilityParams.headless == true)
        #expect(enrollStartParams.proofToken == proofToken)
        #expect(enrollStartParams.accessToken == accessToken)
        #expect(enrollStartParams.headless == true)
    }

    @Test func `Passkey enroll maps local attestation operation failure and clears active controller`() async throws {
        let accessToken = FlowFixtures.accessToken(id: "attestation-failure@example.com")
        let attestationFailure = PasskeyAttestationOperationFailure.access(
            .unauthorized(errorCode: .unauthorized, message: "Attestation proof expired")
        )
        let harness = FlowTestHarness(
            loginResult: .success(FlowFixtures.loginSuccess()),
            passkeyAttestationResult: .failure(attestationFailure)
        )
        let flow = makePasskeyEnrollFlow(harness: harness)
        var context = PasskeyEnrollFlowContext()
        context.accessToken = accessToken

        let controller = flow.start(context)
        let failure = try await requireFailure(controller.whenSettled())
        let operationFailure = try requirePasskeyEnrollOperationFailure(
            failure,
            operationType: .passkeyCreation,
            expectedErrorCode: .unauthorized,
            expectedMessage: "Passkey attestation failed: Attestation proof expired"
        )

        #expect(operationFailure.operationID == harness.passkeyAttestation.startedControllers.first?.operationID)
        try requireAttestationFailure(operationFailure.failure, expectedMessage: attestationFailure.message)
        #expect(harness.passkeyAttestation.startParams.count == 1)
        #expect(harness.passkeyEnroll.startParams.isEmpty)

        controller.abort(reason: .userClose(details: "late abort after attestation failure"))
        try await assertCachedFlowFailure(controller, matches: failure)
        #expect(harness.passkeyAttestation.startedControllers.first?.abortReasons.get().isEmpty == true)
    }

    @Test func `Passkey enroll maps enroll operation failure after local attestation and clears active controller`() async throws {
        let accessToken = FlowFixtures.accessToken(id: "enroll-failure@example.com")
        let proofToken = ProofToken(token: "attested-proof")
        let enrollFailure = PasskeyEnrollOperationFailure.access(
            .forbidden(errorCode: .forbidden, message: "Enroll forbidden")
        )
        let harness = FlowTestHarness(
            loginResult: .success(FlowFixtures.loginSuccess()),
            passkeyAttestationResult: .success(FlowFixtures.attestationResponse(proofToken: proofToken)),
            passkeyEnrollResult: .failure(enrollFailure)
        )
        let flow = makePasskeyEnrollFlow(harness: harness)
        var context = PasskeyEnrollFlowContext()
        context.accessToken = accessToken
        context.headless = true

        let controller = flow.start(context)
        let failure = try await requireFailure(controller.whenSettled())
        let operationFailure = try requirePasskeyEnrollOperationFailure(
            failure,
            operationType: .passkeyEnrollment,
            expectedErrorCode: .forbidden,
            expectedMessage: "Passkey enroll failed: Enroll forbidden"
        )

        #expect(operationFailure.operationID == harness.passkeyEnroll.startedControllers.first?.operationID)
        try requireEnrollFailure(operationFailure.failure, expectedMessage: enrollFailure.message)
        #expect(harness.passkeyAttestation.startParams.count == 1)
        let enrollStartParams = try requireRecordedValue(
            harness.passkeyEnroll.startParams,
            "Expected failed passkey enroll start params"
        )
        #expect(enrollStartParams.proofToken == proofToken)

        controller.abort(reason: .userClose(details: "late abort after enroll failure"))
        try await assertCachedFlowFailure(controller, matches: failure)
        #expect(harness.passkeyAttestation.startedControllers.first?.abortReasons.get().isEmpty == true)
        #expect(harness.passkeyEnroll.startedControllers.first?.abortReasons.get().isEmpty == true)
    }
}

private func makePasskeyEnrollFlow(
    harness: FlowTestHarness,
    context: Context? = nil,
    userJourney: (any UserJourney)? = nil
) -> PasskeyEnrollFlowImpl {
    PasskeyEnrollFlowImpl(
        ownIDOperation: harness.operation,
        coder: harness.coder,
        loginIdValidator: harness.validator,
        userJourney: userJourney,
        taskScope: harness.taskScope,
        context: context,
        logger: nil
    )
}

private extension PasskeyEnrollFlowContractTests {
    static let traceParent = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
}

private func makeHeadlessPasskeyEnrollContext(
    accessToken: AccessToken,
    proofToken: ProofToken,
    traceParent: String
) -> PasskeyEnrollFlowContext {
    var context = PasskeyEnrollFlowContext()
    context.accessToken = accessToken
    context.proofToken = proofToken
    context.headless = true
    context.traceParent = traceParent
    return context
}

private func assertHeadlessPasskeyEnrollJourneyStarted(
    _ userJourney: RecordingFlowUserJourney,
    traceParent: String,
    loginID: LoginID,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws {
    #expect(
        userJourney.startedFlows.get()
            == [RecordedUserJourneyFlow(name: "headless-passkey-enroll", source: .explicit, traceParent: traceParent)],
        sourceLocation: sourceLocation
    )
    #expect(userJourney.userInfo.get() == [loginID], sourceLocation: sourceLocation)
}

private func requireMissingAccessToken(
    _ failure: PasskeyEnrollFlowFailure,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws -> (ErrorCode, String) {
    switch failure {
    case .input(.missingAccessToken(let errorCode, let message)):
        return (errorCode, message)
    default:
        return try #require(
            nil as (ErrorCode, String)?,
            "Expected missing access token failure, got \(failure)",
            sourceLocation: sourceLocation
        )
    }
}

private func requirePasskeyEnrollOperationFailure(
    _ failure: PasskeyEnrollFlowFailure,
    operationType: OperationType,
    expectedErrorCode: ErrorCode,
    expectedMessage: String,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws -> (operationID: OperationID?, failure: (any OperationFailure)?) {
    guard case .operationFailed(
        let actualOperationType,
        let errorCode,
        let message,
        let operationID,
        let operationFailure,
        _
    ) = failure else {
        return try #require(
            nil as (operationID: OperationID?, failure: (any OperationFailure)?)?,
            "Expected operationFailed, got \(failure)",
            sourceLocation: sourceLocation
        )
    }

    #expect(actualOperationType == operationType, sourceLocation: sourceLocation)
    #expect(errorCode == expectedErrorCode, sourceLocation: sourceLocation)
    #expect(message == expectedMessage, sourceLocation: sourceLocation)
    return (operationID, operationFailure)
}

private func requireAttestationFailure(
    _ failure: (any OperationFailure)?,
    expectedMessage: String,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws {
    let failure = try #require(
        failure as? PasskeyAttestationOperationFailure,
        "Expected nested passkey attestation failure",
        sourceLocation: sourceLocation
    )
    #expect(failure.errorCode == .unauthorized, sourceLocation: sourceLocation)
    #expect(failure.message == expectedMessage, sourceLocation: sourceLocation)
}

private func requireEnrollFailure(
    _ failure: (any OperationFailure)?,
    expectedMessage: String,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws {
    let failure = try #require(
        failure as? PasskeyEnrollOperationFailure,
        "Expected nested passkey enroll failure",
        sourceLocation: sourceLocation
    )
    #expect(failure.errorCode == .forbidden, sourceLocation: sourceLocation)
    #expect(failure.message == expectedMessage, sourceLocation: sourceLocation)
}

private func assertCachedFlowFailure(
    _ controller: any PasskeyEnrollController,
    matches failure: PasskeyEnrollFlowFailure,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) async throws {
    let cachedFailure = try await requireFailure(controller.whenSettled(), sourceLocation: sourceLocation)
    #expect(cachedFailure.errorCode == failure.errorCode, sourceLocation: sourceLocation)
    #expect(cachedFailure.message == failure.message, sourceLocation: sourceLocation)
}
