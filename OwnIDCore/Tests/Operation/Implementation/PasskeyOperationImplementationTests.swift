import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

// Covers: OPS-110, OPS-180
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

    @Test func `Passkey assertion verify failure settles terminally and cleans registry`() async throws {
        let assertionResult = testAssertionResult()
        let ui = await FakePasskeyAssertionUI(result: .success(assertionResult))
        let apiController = FakePasskeyAssertionAPIController(
            verifyResult: .failure(
                .badRequest(
                    .invalidChallenge(
                        errorCode: .invalidChallenge,
                        message: "Assertion challenge expired",
                        challengeID: ChallengeID("assertion-expired")
                    )
                )
            )
        )
        let registry = OperationRegistryImpl(logger: nil)
        let operation = makeAssertionOperation(
            ui: ui,
            api: FakePasskeyAssertionAPI(apiController: apiController),
            registry: registry
        )

        let controller = operation.start(params: PasskeyAssertionOperationParams(loginID: testLoginID()))
        let result = try await withOperationTimeout("passkey assertion verify failure") { await controller.whenSettled() }

        let failure = try requireOperationFailure(result)
        try requireAssertionInvalidChallenge(failure, challengeID: ChallengeID("assertion-expired"))
        #expect(apiController.assertionResults.get().map(\.id) == [assertionResult.id])
        try await assertAssertionCompletedState(operation, matches: failure)
        controller.abort(reason: .userClose(details: "late abort after assertion verify failure"))
        try await assertCachedOperationFailure(controller, matches: failure)
        #expect(apiController.cancelReasons.get().isEmpty)
        await assertRegistryEmpty(registry)
    }

    private func makeAssertionOperation(
        ui: FakePasskeyAssertionUI,
        api: FakePasskeyAssertionAPI,
        registry: OperationRegistryImpl = OperationRegistryImpl(logger: nil)
    ) -> PasskeyAssertionOperationImpl {
        PasskeyAssertionOperationImpl(
            operationType: .passkeyAuth,
            operationRegistry: registry,
            ui: ui,
            api: api,
            taskScope: testTaskScope(),
            context: nil,
            loginIDValidator: FakeLoginIDValidator(),
            logger: nil
        )
    }
}

// Covers: OPS-160, OPS-190
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

    @Test func `Passkey attestation verify failure settles terminally and cleans registry`() async throws {
        let attestationResult = testAttestationResult()
        let ui = await FakePasskeyAttestationUI(result: .success(attestationResult))
        let apiController = FakePasskeyAttestationAPIController(
            verifyResult: .failure(.unauthorized(errorCode: .unauthorized, message: "Attestation token expired"))
        )
        let registry = OperationRegistryImpl(logger: nil)
        let operation = makeAttestationOperation(
            ui: ui,
            api: FakePasskeyAttestationAPI(apiController: apiController),
            registry: registry
        )

        let controller = operation.start(params: PasskeyAttestationOperationParams(loginID: testLoginID()))
        let result = try await withOperationTimeout("passkey attestation verify failure") { await controller.whenSettled() }

        let failure = try requireOperationFailure(result)
        try requireAttestationUnauthorized(failure)
        #expect(apiController.attestationResults.get().map(\.id) == [attestationResult.id])
        try await assertAttestationCompletedState(operation, matches: failure)
        controller.abort(reason: .userClose(details: "late abort after attestation verify failure"))
        try await assertCachedOperationFailure(controller, matches: failure)
        #expect(apiController.cancelReasons.get().isEmpty)
        await assertRegistryEmpty(registry)
    }

    private func makeAttestationOperation(
        ui: FakePasskeyAttestationUI,
        api: FakePasskeyAttestationAPI,
        registry: OperationRegistryImpl = OperationRegistryImpl(logger: nil)
    ) -> PasskeyAttestationOperationImpl {
        PasskeyAttestationOperationImpl(
            operationType: .passkeyCreation,
            operationRegistry: registry,
            ui: ui,
            api: api,
            taskScope: testTaskScope(),
            context: nil,
            loginIDValidator: FakeLoginIDValidator(),
            logger: nil
        )
    }
}

// Covers: OPS-130, OPS-200
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

    @Test func `Passkey enroll API failure settles terminally and cleans registry`() async throws {
        let api = FakePasskeyEnrollAPI(
            result: .failure(
                .failedDependency(
                    .providerFailed(errorCode: .integrationError, message: "Enroll provider failed", scope: .data)
                )
            )
        )
        let registry = OperationRegistryImpl(logger: nil)
        let operation = makeEnrollOperation(api: api, registry: registry)

        let controller = operation.start(
            params: PasskeyEnrollOperationParams(
                proofToken: testProofToken("proof-token"),
                accessToken: testAccessToken("access-token")
            )
        )
        let result = try await withOperationTimeout("passkey enroll API failure") { await controller.whenSettled() }

        let failure = try requireOperationFailure(result)
        try requireEnrollProviderFailed(failure)
        #expect(api.params.get().map(\.proofToken) == [testProofToken("proof-token")])
        try await assertEnrollCompletedState(operation, matches: failure)
        controller.abort(reason: .userClose(details: "late abort after enroll API failure"))
        try await assertCachedOperationFailure(controller, matches: failure)
        await assertRegistryEmpty(registry)
    }

    private func makeEnrollOperation(
        api: FakePasskeyEnrollAPI,
        context: Context? = nil,
        registry: OperationRegistryImpl = OperationRegistryImpl(logger: nil)
    ) -> PasskeyEnrollOperationImpl {
        PasskeyEnrollOperationImpl(
            operationType: .passkeyEnrollment,
            operationRegistry: registry,
            api: api,
            taskScope: testTaskScope(),
            context: context,
            logger: nil
        )
    }
}

private func requireAssertionInvalidChallenge(
    _ failure: PasskeyAssertionOperationFailure,
    challengeID: ChallengeID,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws {
    guard case .challenge(.invalid(let errorCode, let message, let actualChallengeID, _)) = failure else {
        return try #require(
            nil as Void?,
            "Expected assertion invalid challenge failure, got \(failure)",
            sourceLocation: sourceLocation
        )
    }
    #expect(errorCode == .invalidChallenge, sourceLocation: sourceLocation)
    #expect(message == "Assertion challenge expired", sourceLocation: sourceLocation)
    #expect(actualChallengeID == challengeID, sourceLocation: sourceLocation)
}

private func requireAttestationUnauthorized(
    _ failure: PasskeyAttestationOperationFailure,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws {
    guard case .access(.unauthorized(let errorCode, let message, _)) = failure else {
        return try #require(
            nil as Void?,
            "Expected attestation unauthorized failure, got \(failure)",
            sourceLocation: sourceLocation
        )
    }
    #expect(errorCode == .unauthorized, sourceLocation: sourceLocation)
    #expect(message == "Attestation token expired", sourceLocation: sourceLocation)
}

private func requireEnrollProviderFailed(
    _ failure: PasskeyEnrollOperationFailure,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws {
    guard case .integration(.providerFailed(let errorCode, let message, _)) = failure else {
        return try #require(
            nil as Void?,
            "Expected enroll provider failure, got \(failure)",
            sourceLocation: sourceLocation
        )
    }
    #expect(errorCode == .integrationError, sourceLocation: sourceLocation)
    #expect(message == "Enroll provider failed", sourceLocation: sourceLocation)
}

private func assertCachedOperationFailure<Success: Sendable, Failure: OperationFailure>(
    _ controller: any OperationController<Success, Failure>,
    matches failure: Failure,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) async throws {
    let cachedFailure = try requireOperationFailure(await controller.whenSettled(), sourceLocation: sourceLocation)
    #expect(cachedFailure.errorCode == failure.errorCode, sourceLocation: sourceLocation)
    #expect(cachedFailure.message == failure.message, sourceLocation: sourceLocation)
}

private func assertAssertionCompletedState(
    _ operation: PasskeyAssertionOperationImpl,
    matches failure: PasskeyAssertionOperationFailure,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) async throws {
    let stream = await MainActor.run { operation.stateStream() }
    var iterator = stream.makeAsyncIterator()
    let state = try #require(await iterator.next(), sourceLocation: sourceLocation)
    guard case .completed(let result) = state else {
        return try #require(nil as Void?, "Expected completed assertion state, got \(state)", sourceLocation: sourceLocation)
    }
    let completedFailure = try requireOperationFailure(result, sourceLocation: sourceLocation)
    #expect(completedFailure.description == failure.description, sourceLocation: sourceLocation)
}

private func assertAttestationCompletedState(
    _ operation: PasskeyAttestationOperationImpl,
    matches failure: PasskeyAttestationOperationFailure,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) async throws {
    let stream = await MainActor.run { operation.stateStream() }
    var iterator = stream.makeAsyncIterator()
    let state = try #require(await iterator.next(), sourceLocation: sourceLocation)
    guard case .completed(let result) = state else {
        return try #require(nil as Void?, "Expected completed attestation state, got \(state)", sourceLocation: sourceLocation)
    }
    let completedFailure = try requireOperationFailure(result, sourceLocation: sourceLocation)
    #expect(completedFailure.description == failure.description, sourceLocation: sourceLocation)
}

private func assertEnrollCompletedState(
    _ operation: PasskeyEnrollOperationImpl,
    matches failure: PasskeyEnrollOperationFailure,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) async throws {
    let stream = await MainActor.run { operation.stateStream() }
    var iterator = stream.makeAsyncIterator()
    let state = try #require(await iterator.next(), sourceLocation: sourceLocation)
    guard case .completed(let result) = state else {
        return try #require(nil as Void?, "Expected completed enroll state, got \(state)", sourceLocation: sourceLocation)
    }
    let completedFailure = try requireOperationFailure(result, sourceLocation: sourceLocation)
    #expect(completedFailure.description == failure.description, sourceLocation: sourceLocation)
}

@MainActor
private func assertRegistryEmpty(
    _ registry: OperationRegistryImpl,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) {
    #expect(registry.operations.isEmpty, sourceLocation: sourceLocation)
}
