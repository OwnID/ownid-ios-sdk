import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

struct PasskeyAssertionOperationImplementationTests {

    @Test func `Passkey assertion passes options to UI and verifies result`() async throws {
        let assertionResult = testAssertionResult()
        let ui = await FakePasskeyAssertionUI(result: .success(assertionResult))
        let apiController = FakePasskeyAssertionAPIController(
            assertionOptions: testAssertionOptions("assertion-options-challenge"),
            verifyResult: .success(testAccessToken("verified-access-token"))
        )
        let operation = makeAssertionOperation(ui: ui, api: FakePasskeyAssertionAPI(apiController: apiController))

        let controller = operation.start(params: PasskeyAssertionOperationParams(loginID: testLoginID()))
        let result = try await withOperationTimeout("passkey assertion success") { await controller.whenSettled() }

        #expect(result.getOrNil() == testAccessToken("verified-access-token"))
        #expect(await ui.receivedOptions?.challenge == ChallengeID("assertion-options-challenge"))
        #expect(apiController.assertionResults.get().map(\.id) == [assertionResult.id])
        #expect(apiController.cancelReasons.get().isEmpty)
    }

    @Test func `Passkey assertion cancellation cancels server challenge`() async throws {
        let ui = await FakePasskeyAssertionUI(result: .canceled(.userClose(details: "passkey UI dismissed")))
        let apiController = FakePasskeyAssertionAPIController()
        let operation = makeAssertionOperation(ui: ui, api: FakePasskeyAssertionAPI(apiController: apiController))

        let controller = operation.start(params: PasskeyAssertionOperationParams(loginID: testLoginID()))
        let result = try await withOperationTimeout("passkey assertion cancellation") { await controller.whenSettled() }

        let reason = try requireOperationCancellation(result)
        #expect(reason.description == Reason.userClose(details: "passkey UI dismissed").description)
        #expect(apiController.assertionResults.get().isEmpty)
        #expect(apiController.cancelReasons.get().map(\.description) == [reason.description])
    }

    @Test func `Passkey assertion no credential maps to credential failure`() async throws {
        let ui = await FakePasskeyAssertionUI(result: .failure(.passkeysNoCredential("No matching credential", nil, nil)))
        let apiController = FakePasskeyAssertionAPIController()
        let operation = makeAssertionOperation(ui: ui, api: FakePasskeyAssertionAPI(apiController: apiController))

        let controller = operation.start(params: PasskeyAssertionOperationParams(loginID: testLoginID()))
        let result = try await withOperationTimeout("passkey assertion no credential") { await controller.whenSettled() }

        let failure = try requireOperationFailure(result)
        #expect(failure.errorCode == .noApplicablePasskeys)
        #expect(apiController.assertionResults.get().isEmpty)
        #expect(apiController.cancelReasons.get().count == 1)
    }

    private func makeAssertionOperation(ui: FakePasskeyAssertionUI, api: FakePasskeyAssertionAPI) -> PasskeyAssertionOperationImpl {
        PasskeyAssertionOperationImpl(
            operationType: .passkeyAuth,
            operationRegistry: OperationRegistryImpl(logger: nil),
            ui: ui,
            api: api,
            taskScope: testTaskScope(),
            context: nil,
            loginIDValidator: FakeLoginIDValidator(),
            logger: nil
        )
    }
}

struct PasskeyAttestationOperationImplementationTests {

    @Test func `Passkey attestation passes options to UI and verifies result`() async throws {
        let attestationResult = testAttestationResult()
        let ui = await FakePasskeyAttestationUI(result: .success(attestationResult))
        let apiController = FakePasskeyAttestationAPIController(
            attestationOptions: testAttestationOptions("attestation-options-challenge"),
            verifyResult: .success(testAttestationResponse(proofToken: testProofToken("verified-proof-token")))
        )
        let operation = makeAttestationOperation(ui: ui, api: FakePasskeyAttestationAPI(apiController: apiController))

        let controller = operation.start(params: PasskeyAttestationOperationParams(loginID: testLoginID()))
        let result = try await withOperationTimeout("passkey attestation success") { await controller.whenSettled() }

        let response = try requireOperationSuccess(result)
        #expect(response.proofToken == testProofToken("verified-proof-token"))
        #expect(await ui.receivedOptions?.challenge == ChallengeID("attestation-options-challenge"))
        #expect(apiController.attestationResults.get().map(\.id) == [attestationResult.id])
        #expect(apiController.cancelReasons.get().isEmpty)
    }

    @Test func `Passkey attestation cancellation cancels server challenge`() async throws {
        let ui = await FakePasskeyAttestationUI(result: .canceled(.userClose(details: "passkey UI dismissed")))
        let apiController = FakePasskeyAttestationAPIController()
        let operation = makeAttestationOperation(ui: ui, api: FakePasskeyAttestationAPI(apiController: apiController))

        let controller = operation.start(params: PasskeyAttestationOperationParams(loginID: testLoginID()))
        let result = try await withOperationTimeout("passkey attestation cancellation") { await controller.whenSettled() }

        let reason = try requireOperationCancellation(result)
        #expect(reason.description == Reason.userClose(details: "passkey UI dismissed").description)
        #expect(apiController.attestationResults.get().isEmpty)
        #expect(apiController.cancelReasons.get().map(\.description) == [reason.description])
    }

    @Test func `Passkey attestation provider failure becomes integration failure`() async throws {
        let ui = await FakePasskeyAttestationUI(result: .failure(.general("Passkey provider failed", nil, nil)))
        let apiController = FakePasskeyAttestationAPIController()
        let operation = makeAttestationOperation(ui: ui, api: FakePasskeyAttestationAPI(apiController: apiController))

        let controller = operation.start(params: PasskeyAttestationOperationParams(loginID: testLoginID()))
        let result = try await withOperationTimeout("passkey attestation provider failure") { await controller.whenSettled() }

        let failure = try requireOperationFailure(result)
        #expect(failure.errorCode == .passkeyNotCreated)
        #expect(apiController.attestationResults.get().isEmpty)
        #expect(apiController.cancelReasons.get().count == 1)
    }

    private func makeAttestationOperation(
        ui: FakePasskeyAttestationUI,
        api: FakePasskeyAttestationAPI
    ) -> PasskeyAttestationOperationImpl {
        PasskeyAttestationOperationImpl(
            operationType: .passkeyCreation,
            operationRegistry: OperationRegistryImpl(logger: nil),
            ui: ui,
            api: api,
            taskScope: testTaskScope(),
            context: nil,
            loginIDValidator: FakeLoginIDValidator(),
            logger: nil
        )
    }
}

struct PasskeyEnrollOperationImplementationTests {

    @Test func `Passkey enroll sends explicit access token and proof token to API`() async throws {
        let api = FakePasskeyEnrollAPI()
        let operation = makeEnrollOperation(api: api)

        let controller = operation.start(
            params: PasskeyEnrollOperationParams(
                proofToken: testProofToken("proof-token"),
                accessToken: testAccessToken("explicit-access-token")
            )
        )
        let result = try await withOperationTimeout("passkey enroll explicit token") { await controller.whenSettled() }

        try requireOperationSuccess(result)
        let params = try #require(api.params.get().first ?? nil)
        #expect(params.proofToken == testProofToken("proof-token"))
        #expect(params.accessToken == testAccessToken("explicit-access-token"))
    }

    @Test func `Passkey enroll falls back to context access token before API`() async throws {
        let api = FakePasskeyEnrollAPI()
        let context = testContext(authz: .fromToken(testAccessToken("context-access-token")))
        let operation = makeEnrollOperation(api: api, context: context)

        let controller = operation.start(
            params: PasskeyEnrollOperationParams(proofToken: testProofToken("proof-token"), accessToken: nil)
        )
        let result = try await withOperationTimeout("passkey enroll context token") { await controller.whenSettled() }

        try requireOperationSuccess(result)
        let params = try #require(api.params.get().first ?? nil)
        #expect(params.proofToken == testProofToken("proof-token"))
        #expect(params.accessToken == testAccessToken("context-access-token"))
    }

    @Test func `Passkey enroll fails before API when access token is missing`() async throws {
        let api = FakePasskeyEnrollAPI()
        let operation = makeEnrollOperation(api: api)

        let controller = operation.start(
            params: PasskeyEnrollOperationParams(proofToken: testProofToken("proof-token"), accessToken: nil)
        )
        let result = try await withOperationTimeout("passkey enroll missing access token") { await controller.whenSettled() }

        let failure = try requireOperationFailure(result)
        #expect(failure.errorCode == .invalidArgument)
        #expect(failure.message == "AccessToken and ProofToken required")
        #expect(api.params.get().isEmpty)
    }

    private func makeEnrollOperation(api: FakePasskeyEnrollAPI, context: Context? = nil) -> PasskeyEnrollOperationImpl {
        PasskeyEnrollOperationImpl(
            operationType: .passkeyEnrollment,
            operationRegistry: OperationRegistryImpl(logger: nil),
            api: api,
            taskScope: testTaskScope(),
            context: context,
            logger: nil
        )
    }
}
