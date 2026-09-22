import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

// Covers: OPS-120
struct SocialOperationImplementationTests {

    @Test(arguments: SocialOperationCase.allCases)
    func `Social success completes OIDC challenge`(_ testCase: SocialOperationCase) async throws {
        let observation = try await runSocialSuccess(testCase)

        #expect(observation.response.accessToken == testAccessToken("\(testCase.key)-access-token"))
        #expect(observation.response.provider == testCase.provider)
        #expect(observation.idTokens == ["\(testCase.key)-id-token"])
        #expect(observation.receivedClientID == "\(testCase.key)-client-id")
        #expect(observation.receivedNonce == "\(testCase.key)-challenge")
        #expect(observation.apiParams.count == 1)
        #expect(observation.apiParams.first??.provider == testCase.provider)
        #expect(observation.apiParams.first??.accessToken == testCase.inputAccessToken)
    }

    @Test(arguments: SocialOperationCase.allCases)
    func `Social cancellation cancels OIDC challenge`(_ testCase: SocialOperationCase) async throws {
        let observation = try await runSocialCancellation(testCase)

        #expect(observation.reason.description == Reason.userClose(details: "\(testCase.displayName) dismissed").description)
        #expect(observation.idTokens.isEmpty)
        #expect(observation.cancelReasons.map(\.description) == [observation.reason.description])
    }

    @Test(arguments: SocialOperationCase.allCases)
    func `Social provider failure becomes terminal integration failure`(_ testCase: SocialOperationCase) async throws {
        let observation = try await runSocialProviderFailure(testCase)

        #expect(observation.errorCode == .oidcFailed)
        #expect(observation.providerMessage == "\(testCase.displayName) provider failed")
        #expect(observation.cancelReasons.count == 1)
    }

    @Test(arguments: SocialOperationCase.allCases)
    func `Social OIDC start failure settles before provider UI`(_ testCase: SocialOperationCase) async throws {
        let observation = try await runSocialStartFailure(testCase)

        #expect(observation.errorCode == .invalidArgument)
        #expect(observation.providerCallCount == 0)
        #expect(observation.apiParams.count == 1)
        #expect(observation.apiParams.first??.provider == testCase.provider)
    }

    @Test(arguments: SocialOperationCase.allCases, SocialCompletionOutcome.allCases)
    func `Social OIDC completion terminal is preserved`(
        _ testCase: SocialOperationCase,
        _ completionOutcome: SocialCompletionOutcome
    ) async throws {
        let observation = try await runSocialCompletion(testCase, outcome: completionOutcome)

        switch completionOutcome {
        case .failure:
            #expect(observation.failureCode == .invalidChallenge)
            #expect(observation.cancellationReason == nil)
        case .canceled:
            #expect(observation.failureCode == nil)
            let reason = try #require(observation.cancellationReason)
            guard case .systemError = reason else {
                Issue.record("Expected a system-error cancellation, got \(reason)")
                return
            }
        }
        #expect(observation.idTokens == ["\(testCase.key)-id-token"])
        #expect(observation.cancelReasons.isEmpty)
    }

    @Test(arguments: SocialOperationCase.allCases)
    func `Social active abort preserves reason and performs UI and API cleanup`(_ testCase: SocialOperationCase) async throws {
        let observation = try await runSocialActiveAbort(testCase)

        guard case .systemError(let details) = observation.settledReason else {
            Issue.record("Expected the caller-supplied system-error cancellation, got \(observation.settledReason)")
            return
        }
        #expect(details == "Social presentation aborted")
        #expect(observation.cancelReasonCount == 1)
        #expect(observation.uiCancelCount == 1)
    }

    private func runSocialSuccess(_ testCase: SocialOperationCase) async throws -> SocialSuccessObservation {
        let socialResult = SocialResult.success(id: "\(testCase.key)-user", idToken: "\(testCase.key)-id-token")
        let apiController = FakeOIDCAPIController(
            challenge: testSocialChallenge(provider: testCase.provider, challenge: "\(testCase.key)-challenge"),
            completeResult: .success(testSocialToken(provider: testCase.provider, token: "\(testCase.key)-access-token"))
        )

        switch testCase.provider {
        case .apple:
            let ui = await FakeAppleSignInUI(result: socialResult)
            let operation = makeAppleOperation(ui: ui, apiController: apiController)
            let result = try await withOperationTimeout("\(testCase.displayName) social success") {
                await operation.operation.start(params: SignInWithAppleOperationParams(accessToken: testCase.inputAccessToken))
                    .whenSettled()
            }
            return SocialSuccessObservation(
                response: try requireOperationSuccess(result),
                idTokens: apiController.idTokens.get(),
                apiParams: operation.api.params.get(),
                receivedClientID: await ui.receivedClientID,
                receivedNonce: await ui.receivedNonce
            )

        case .google:
            let ui = await FakeGoogleSignInUI(result: socialResult)
            let operation = makeGoogleOperation(ui: ui, apiController: apiController)
            let result = try await withOperationTimeout("\(testCase.displayName) social success") {
                await operation.operation.start(params: SignInWithGoogleOperationParams(accessToken: testCase.inputAccessToken))
                    .whenSettled()
            }
            return SocialSuccessObservation(
                response: try requireOperationSuccess(result),
                idTokens: apiController.idTokens.get(),
                apiParams: operation.api.params.get(),
                receivedClientID: await ui.receivedClientID,
                receivedNonce: await ui.receivedNonce
            )
        }
    }

    private func runSocialCancellation(_ testCase: SocialOperationCase) async throws -> SocialCancellationObservation {
        let socialResult = SocialResult.canceled(reason: .userClose(details: "\(testCase.displayName) dismissed"))
        let apiController = FakeOIDCAPIController(
            challenge: testSocialChallenge(provider: testCase.provider),
            completeResult: .success(testSocialToken(provider: testCase.provider))
        )

        switch testCase.provider {
        case .apple:
            let ui = await FakeAppleSignInUI(result: socialResult)
            let operation = makeAppleOperation(ui: ui, apiController: apiController)
            let result = try await withOperationTimeout("\(testCase.displayName) social cancellation") {
                await operation.operation.start(params: SignInWithAppleOperationParams()).whenSettled()
            }
            return SocialCancellationObservation(
                reason: try requireOperationCancellation(result),
                idTokens: apiController.idTokens.get(),
                cancelReasons: apiController.cancelReasons.get()
            )

        case .google:
            let ui = await FakeGoogleSignInUI(result: socialResult)
            let operation = makeGoogleOperation(ui: ui, apiController: apiController)
            let result = try await withOperationTimeout("\(testCase.displayName) social cancellation") {
                await operation.operation.start(params: SignInWithGoogleOperationParams()).whenSettled()
            }
            return SocialCancellationObservation(
                reason: try requireOperationCancellation(result),
                idTokens: apiController.idTokens.get(),
                cancelReasons: apiController.cancelReasons.get()
            )
        }
    }

    private func runSocialProviderFailure(_ testCase: SocialOperationCase) async throws -> SocialFailureObservation {
        let socialResult = SocialResult.fail(error: .general("\(testCase.displayName) provider failed"))
        let apiController = FakeOIDCAPIController(
            challenge: testSocialChallenge(provider: testCase.provider),
            completeResult: .success(testSocialToken(provider: testCase.provider))
        )

        switch testCase.provider {
        case .apple:
            let ui = await FakeAppleSignInUI(result: socialResult)
            let operation = makeAppleOperation(ui: ui, apiController: apiController)
            let result = try await withOperationTimeout("\(testCase.displayName) social failure") {
                await operation.operation.start(params: SignInWithAppleOperationParams()).whenSettled()
            }
            let failure = try requireOperationFailure(result)
            return SocialFailureObservation(
                errorCode: failure.errorCode,
                providerMessage: appleProviderMessage(failure),
                cancelReasons: apiController.cancelReasons.get()
            )

        case .google:
            let ui = await FakeGoogleSignInUI(result: socialResult)
            let operation = makeGoogleOperation(ui: ui, apiController: apiController)
            let result = try await withOperationTimeout("\(testCase.displayName) social failure") {
                await operation.operation.start(params: SignInWithGoogleOperationParams()).whenSettled()
            }
            let failure = try requireOperationFailure(result)
            return SocialFailureObservation(
                errorCode: failure.errorCode,
                providerMessage: googleProviderMessage(failure),
                cancelReasons: apiController.cancelReasons.get()
            )
        }
    }

    private func runSocialStartFailure(_ testCase: SocialOperationCase) async throws -> SocialStartFailureObservation {
        let api = FakeOIDCAPI(
            startResult: .failure(
                .badRequest(.invalidArgument(errorCode: .invalidArgument, message: "OIDC start rejected"))
            )
        )

        switch testCase.provider {
        case .apple:
            let ui = await FakeAppleSignInUI(result: .success(id: "unused", idToken: "unused"))
            let operation = makeAppleOperation(ui: ui, api: api)
            let result = try await withOperationTimeout("Apple OIDC start failure") {
                await operation.operation.start(params: SignInWithAppleOperationParams()).whenSettled()
            }
            return SocialStartFailureObservation(
                errorCode: try requireOperationFailure(result).errorCode,
                providerCallCount: await ui.signInCallCount,
                apiParams: api.params.get()
            )

        case .google:
            let ui = await FakeGoogleSignInUI(result: .success(id: "unused", idToken: "unused"))
            let operation = makeGoogleOperation(ui: ui, api: api)
            let result = try await withOperationTimeout("Google OIDC start failure") {
                await operation.operation.start(params: SignInWithGoogleOperationParams()).whenSettled()
            }
            return SocialStartFailureObservation(
                errorCode: try requireOperationFailure(result).errorCode,
                providerCallCount: await ui.signInCallCount,
                apiParams: api.params.get()
            )
        }
    }

    private func runSocialCompletion(
        _ testCase: SocialOperationCase,
        outcome: SocialCompletionOutcome
    ) async throws -> SocialCompletionObservation {
        let completeResult: APIResult<AccessTokenWithUserInfo, OIDCCompleteAPIFailure> =
            switch outcome {
            case .failure:
                .failure(
                    .badRequest(
                        .invalidChallenge(
                            errorCode: .invalidChallenge,
                            message: "OIDC challenge expired",
                            challengeID: ChallengeID("\(testCase.key)-challenge")
                        )
                    )
                )
            case .canceled:
                .canceled
            }
        let apiController = FakeOIDCAPIController(
            challenge: testSocialChallenge(provider: testCase.provider, challenge: "\(testCase.key)-challenge"),
            completeResult: completeResult
        )
        let socialResult = SocialResult.success(id: "\(testCase.key)-user", idToken: "\(testCase.key)-id-token")

        switch testCase.provider {
        case .apple:
            let ui = await FakeAppleSignInUI(result: socialResult)
            let operation = makeAppleOperation(ui: ui, apiController: apiController)
            let result = try await withOperationTimeout("Apple OIDC completion \(outcome.rawValue)") {
                await operation.operation.start(params: SignInWithAppleOperationParams()).whenSettled()
            }
            return try socialCompletionObservation(result, apiController: apiController, outcome: outcome)

        case .google:
            let ui = await FakeGoogleSignInUI(result: socialResult)
            let operation = makeGoogleOperation(ui: ui, apiController: apiController)
            let result = try await withOperationTimeout("Google OIDC completion \(outcome.rawValue)") {
                await operation.operation.start(params: SignInWithGoogleOperationParams()).whenSettled()
            }
            return try socialCompletionObservation(result, apiController: apiController, outcome: outcome)
        }
    }

    private func runSocialActiveAbort(_ testCase: SocialOperationCase) async throws -> SocialAbortObservation {
        let expectedReason = Reason.systemError(details: "Social presentation aborted")
        let cancelResult: APIResult<Void, OIDCCancelAPIFailure> =
            testCase.provider == .apple
                ? .failure(.badRequest(.unknown(errorCode: .unknown, message: "OIDC cancellation failed")))
                : .canceled
        let apiController = FakeOIDCAPIController(
            challenge: testSocialChallenge(provider: testCase.provider),
            completeResult: .success(testSocialToken(provider: testCase.provider)),
            cancelResult: cancelResult
        )
        let registry = OperationRegistryImpl(logger: nil)

        switch testCase.provider {
        case .apple:
            let ui = await FakeAppleSignInUI()
            let operation = makeAppleOperation(
                ui: ui,
                api: FakeOIDCAPI(controller: apiController),
                registry: registry
            )
            let controller = operation.operation.start(params: SignInWithAppleOperationParams())
            _ = try await withOperationTimeout("Apple provider UI start") { try await ui.started.waitUnlessCancelled() }
            controller.abort(reason: expectedReason)
            _ = try await withOperationTimeout("Apple OIDC abort cleanup") {
                try await apiController.cancelReason.waitUnlessCancelled()
            }
            _ = try await withOperationTimeout("Apple provider UI cancel") { try await ui.canceled.waitUnlessCancelled() }
            let settledReason = try requireOperationCancellation(
                try await withOperationTimeout("Apple social abort settlement") { await controller.whenSettled() }
            )
            await assertSocialRegistryEmpty(registry)
            return SocialAbortObservation(
                settledReason: settledReason,
                cancelReasonCount: apiController.cancelReasons.get().count,
                uiCancelCount: await ui.cancelCallCount
            )

        case .google:
            let ui = await FakeGoogleSignInUI()
            let operation = makeGoogleOperation(
                ui: ui,
                api: FakeOIDCAPI(controller: apiController),
                registry: registry
            )
            let controller = operation.operation.start(params: SignInWithGoogleOperationParams())
            _ = try await withOperationTimeout("Google provider UI start") { try await ui.started.waitUnlessCancelled() }
            controller.abort(reason: expectedReason)
            _ = try await withOperationTimeout("Google OIDC abort cleanup") {
                try await apiController.cancelReason.waitUnlessCancelled()
            }
            _ = try await withOperationTimeout("Google provider UI cancel") { try await ui.canceled.waitUnlessCancelled() }
            let settledReason = try requireOperationCancellation(
                try await withOperationTimeout("Google social abort settlement") { await controller.whenSettled() }
            )
            await assertSocialRegistryEmpty(registry)
            return SocialAbortObservation(
                settledReason: settledReason,
                cancelReasonCount: apiController.cancelReasons.get().count,
                uiCancelCount: await ui.cancelCallCount
            )
        }
    }

    private func makeAppleOperation(
        ui: FakeAppleSignInUI,
        apiController: FakeOIDCAPIController
    ) -> SocialOperationHarness<SignInWithAppleOperationImpl> {
        makeAppleOperation(ui: ui, api: FakeOIDCAPI(controller: apiController))
    }

    private func makeAppleOperation(
        ui: FakeAppleSignInUI,
        api: FakeOIDCAPI,
        registry: OperationRegistryImpl = OperationRegistryImpl(logger: nil)
    ) -> SocialOperationHarness<SignInWithAppleOperationImpl> {
        return SocialOperationHarness(
            operation: SignInWithAppleOperationImpl(
                operationType: .oidcAuthenticationApple,
                operationRegistry: registry,
                ui: ui,
                api: api,
                taskScope: testTaskScope(),
                context: nil,
                logger: nil
            ),
            api: api
        )
    }

    private func makeGoogleOperation(
        ui: FakeGoogleSignInUI,
        apiController: FakeOIDCAPIController
    ) -> SocialOperationHarness<SignInWithGoogleOperationImpl> {
        makeGoogleOperation(ui: ui, api: FakeOIDCAPI(controller: apiController))
    }

    private func makeGoogleOperation(
        ui: FakeGoogleSignInUI,
        api: FakeOIDCAPI,
        registry: OperationRegistryImpl = OperationRegistryImpl(logger: nil)
    ) -> SocialOperationHarness<SignInWithGoogleOperationImpl> {
        return SocialOperationHarness(
            operation: SignInWithGoogleOperationImpl(
                operationType: .oidcAuthenticationGoogle,
                operationRegistry: registry,
                ui: ui,
                api: api,
                taskScope: testTaskScope(),
                context: nil,
                logger: nil
            ),
            api: api
        )
    }
}

struct SocialOperationCase: Sendable, CustomTestStringConvertible {
    static let allCases = [
        SocialOperationCase(provider: .apple, displayName: "Apple", inputAccessToken: testAccessToken("session-access")),
        SocialOperationCase(provider: .google, displayName: "Google", inputAccessToken: nil),
    ]

    let provider: SocialProviderID
    let displayName: String
    let inputAccessToken: AccessToken?

    var key: String { provider.rawValue.lowercased() }
    var testDescription: String { displayName }
}

enum SocialCompletionOutcome: String, CaseIterable, Sendable {
    case failure
    case canceled
}

@MainActor
private func assertSocialRegistryEmpty(
    _ registry: OperationRegistryImpl,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) {
    #expect(registry.operations.isEmpty, sourceLocation: sourceLocation)
}

private struct SocialOperationHarness<Operation: Sendable>: Sendable {
    let operation: Operation
    let api: FakeOIDCAPI
}

private struct SocialSuccessObservation: Sendable {
    let response: AccessTokenWithUserInfo
    let idTokens: [String]
    let apiParams: [OIDCAPIParams?]
    let receivedClientID: String?
    let receivedNonce: String?
}

private struct SocialCancellationObservation: Sendable {
    let reason: Reason
    let idTokens: [String]
    let cancelReasons: [Reason]
}

private struct SocialFailureObservation: Sendable {
    let errorCode: ErrorCode
    let providerMessage: String?
    let cancelReasons: [Reason]
}

private struct SocialStartFailureObservation: Sendable {
    let errorCode: ErrorCode
    let providerCallCount: Int
    let apiParams: [OIDCAPIParams?]
}

private struct SocialCompletionObservation: Sendable {
    let failureCode: ErrorCode?
    let cancellationReason: Reason?
    let idTokens: [String]
    let cancelReasons: [Reason]
}

private struct SocialAbortObservation: Sendable {
    let settledReason: Reason
    let cancelReasonCount: Int
    let uiCancelCount: Int
}

private func socialCompletionObservation<Failure: OperationFailure>(
    _ result: OperationResult<AccessTokenWithUserInfo, Failure>,
    apiController: FakeOIDCAPIController,
    outcome: SocialCompletionOutcome
) throws -> SocialCompletionObservation {
    switch outcome {
    case .failure:
        return SocialCompletionObservation(
            failureCode: try requireOperationFailure(result).errorCode,
            cancellationReason: nil,
            idTokens: apiController.idTokens.get(),
            cancelReasons: apiController.cancelReasons.get()
        )
    case .canceled:
        return SocialCompletionObservation(
            failureCode: nil,
            cancellationReason: try requireOperationCancellation(result),
            idTokens: apiController.idTokens.get(),
            cancelReasons: apiController.cancelReasons.get()
        )
    }
}

private func appleProviderMessage(_ failure: SignInWithAppleOperationFailure) -> String? {
    guard
        case .integration(.providerFailed(_, _, _, let underlyingError)) = failure,
        let providerError = underlyingError as? SocialResult.Error
    else { return nil }
    return providerError.errorDescription
}

private func googleProviderMessage(_ failure: SignInWithGoogleOperationFailure) -> String? {
    guard
        case .integration(.providerFailed(_, _, _, let underlyingError)) = failure,
        let providerError = underlyingError as? SocialResult.Error
    else { return nil }
    return providerError.errorDescription
}
