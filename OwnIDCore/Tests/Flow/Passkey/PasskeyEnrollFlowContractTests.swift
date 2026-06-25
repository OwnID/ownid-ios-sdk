import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

struct PasskeyEnrollFlowContractTests {

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

    @Test func `Passkey enroll context description lists configured values only`() {
        #expect(PasskeyEnrollFlowContext().description == "PasskeyEnrollFlowContext()")

        var accessOnly = PasskeyEnrollFlowContext()
        accessOnly.accessToken = AccessToken(token: "access-token")
        let accessOnlyDescription = "PasskeyEnrollFlowContext(accessToken=AccessToken(token: access-token))"
        #expect(accessOnly.description == accessOnlyDescription)

        var proofAndHeadlessFalse = PasskeyEnrollFlowContext()
        proofAndHeadlessFalse.proofToken = ProofToken(token: "proof-token")
        proofAndHeadlessFalse.headless = false
        let proofAndHeadlessFalseDescription =
            "PasskeyEnrollFlowContext(proofToken=ProofToken(token: proof-token), headless=false)"
        #expect(proofAndHeadlessFalse.description == proofAndHeadlessFalseDescription)

        var allValues = PasskeyEnrollFlowContext()
        allValues.accessToken = AccessToken(token: "access-token")
        allValues.proofToken = ProofToken(token: "proof-token")
        allValues.headless = true
        let allValuesDescription =
            "PasskeyEnrollFlowContext(accessToken=AccessToken(token: access-token), "
            + "proofToken=ProofToken(token: proof-token), headless=true)"
        #expect(allValues.description == allValuesDescription)
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
}

private func makePasskeyEnrollFlow(
    harness: FlowTestHarness,
    context: Context? = nil
) -> PasskeyEnrollFlowImpl {
    PasskeyEnrollFlowImpl(
        ownIDOperation: harness.operation,
        coder: harness.coder,
        loginIdValidator: harness.validator,
        userJourney: nil,
        taskScope: harness.taskScope,
        context: context,
        logger: nil
    )
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
