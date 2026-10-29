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
        let socialResult = SocialSignInResult.success(id: "\(testCase.key)-user", idToken: "\(testCase.key)-id-token")
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
        let socialResult = SocialSignInResult.canceled(reason: .userClose(details: "\(testCase.displayName) dismissed"))
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
        let socialResult = SocialSignInResult.fail(error: .general("\(testCase.displayName) provider failed"))
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
        let socialResult = SocialSignInResult.success(id: "\(testCase.key)-user", idToken: "\(testCase.key)-id-token")

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
        let providerError = underlyingError as? SocialSignInResult.Error
    else { return nil }
    return providerError.errorDescription
}

private func googleProviderMessage(_ failure: SignInWithGoogleOperationFailure) -> String? {
    guard
        case .integration(.providerFailed(_, _, _, let underlyingError)) = failure,
        let providerError = underlyingError as? SocialSignInResult.Error
    else { return nil }
    return providerError.errorDescription
}

extension SocialOperationImplementationTests {
    @Test(arguments: SocialOperationCase.allCases)
    func `Social abort during OIDC start rejects late activation`(_ testCase: SocialOperationCase) async throws {
        let scope = testTaskScope()
        defer { scope.shutdown() }
        let ui = SocialRaceUI()
        let api = SocialRaceAPIController(provider: testCase.provider)
        let startAPI = SocialRaceStartAPI(controller: api)
        let runtime = try makeSocialRaceRuntime(testCase.provider, scope: scope, ui: ui, api: api, startAPI: startAPI)
        let consumer = try socialRaceConsumer(scope)
        runtime.start()
        _ = try await startAPI.entered.waitForCount(1, "OIDC start entered") { _ in true }
        let reason = Reason.systemError(details: "Abort pending start")
        runtime.abort(reason)
        #expect(try await withOperationTimeout("Pending start abort settles") { try await runtime.whenSettled() } == "canceled:\(reason.description)")
        try await socialRaceJoin([consumer], "Pending start consumer drained")
        let remaining = try socialRaceTaskSnapshot(scope)
        await startAPI.release.set(())
        try await socialRaceJoin(remaining, "Late start response drained")
        #expect(await ui.signInCount == 0)
        #expect(await !runtime.isActive())
        #expect(api.cancelEntered.entries.isEmpty)
    }

    @Test(arguments: SocialOperationCase.allCases, SocialFinishingOutcome.allCases)
    func `Social accepted provider result disables queued challenge timeout`(
        _ testCase: SocialOperationCase, _ outcome: SocialFinishingOutcome
    ) async throws {
        let scope = testTaskScope()
        defer { scope.shutdown() }
        let ui = SocialRaceUI()
        let api = SocialRaceAPIController(provider: testCase.provider, completeFailure: outcome == .tokenFailure)
        let runtime = try makeSocialRaceRuntime(testCase.provider, scope: scope, ui: ui, api: api)
        let consumer = try socialRaceConsumer(scope)
        runtime.start()
        try await withOperationTimeout("Provider UI entered") { try await ui.started.waitUnlessCancelled() }
        await ui.finish(outcome.providerResult)
        if outcome.usesToken {
            _ = try await api.completeEntered.waitForCount(1, "Token completion entered") { _ in true }
        } else {
            _ = try await api.cancelEntered.waitForCount(1, "Provider cleanup entered") { _ in true }
        }
        #expect(await runtime.isActive()) // Provider outcomes still wait for backend completion/cleanup.
        // The real provider event has been consumed. Enqueue the timer's already-fired event before
        // releasing the backend producer, so it must precede the real terminal .complete in the stream.
        await runtime.queuedTimeout()
        await api.cancelRelease.set(())
        await api.completeRelease.set(())
        #expect(try await withOperationTimeout("Provider result settles") { try await runtime.whenSettled() } == outcome.expected)
        try await socialRaceDrain(scope, consumer: consumer)
        #expect(api.cancelEntered.entries.map(\.description) == outcome.cancelReasons)
        #expect(api.completeEntered.entries.count == (outcome.usesToken ? 1 : 0))
        #expect(await ui.cancelCount == 0)
    }

    @Test(arguments: SocialOperationCase.allCases, [SocialFinishingOutcome.tokenSuccess, .providerCanceled, .providerFailed])
    func `Social explicit abort stays valid during completion or provider cleanup`(
        _ testCase: SocialOperationCase, _ outcome: SocialFinishingOutcome
    ) async throws {
        let scope = testTaskScope()
        defer { scope.shutdown() }
        let ui = SocialRaceUI()
        let api = SocialRaceAPIController(provider: testCase.provider, completeFailure: outcome == .tokenFailure)
        let runtime = try makeSocialRaceRuntime(testCase.provider, scope: scope, ui: ui, api: api)
        let consumer = try socialRaceConsumer(scope)
        runtime.start()
        try await withOperationTimeout("Provider UI entered") { try await ui.started.waitUnlessCancelled() }
        await ui.finish(outcome.providerResult)
        if outcome.usesToken {
            _ = try await api.completeEntered.waitForCount(1, "Token completion entered") { _ in true }
        } else {
            _ = try await api.cancelEntered.waitForCount(1, "Provider cleanup entered") { _ in true }
        }
        let caller = Reason.systemError(details: "Explicit abort while finishing")
        runtime.abort(caller)
        #expect(try await withOperationTimeout("Explicit abort settles without backend release") { try await runtime.whenSettled() } == "canceled:\(caller.description)")
        runtime.abort(caller)
        await api.cancelRelease.set(())
        await api.completeRelease.set(())
        try await socialRaceDrain(scope, consumer: consumer)
        #expect(api.cancelEntered.entries.map(\.description) == (outcome.usesToken ? [caller.description] : outcome.cancelReasons))
        #expect(api.completeEntered.entries.count == (outcome.usesToken ? 1 : 0))
        #expect(await ui.cancelCount == 1)
        #expect(try await runtime.whenSettled() == "canceled:\(caller.description)")
    }

    @Test(arguments: SocialOperationCase.allCases, [false, true])
    func `Social abort before provider result cancels API once despite UI callback and repeated abort`(
        _ testCase: SocialOperationCase, _ timeout: Bool
    ) async throws {
        let scope = testTaskScope()
        defer { scope.shutdown() }
        let ui = SocialRaceUI()
        let api = SocialRaceAPIController(provider: testCase.provider)
        let runtime = try makeSocialRaceRuntime(testCase.provider, scope: scope, ui: ui, api: api)
        let consumer = try socialRaceConsumer(scope)
        runtime.start()
        try await withOperationTimeout("Provider UI entered") { try await ui.started.waitUnlessCancelled() }
        let reason = timeout ? Reason.timeout : .systemError(details: "Explicit abort before provider result")
        runtime.abort(reason)
        _ = try await api.cancelEntered.waitForCount(1, "Abort cleanup entered") { _ in true }
        runtime.abort(.systemError(details: "Repeated abort"))
        #expect(try await withOperationTimeout("Abort settles before API cleanup") { try await runtime.whenSettled() } == "canceled:\(reason.description)")
        await api.cancelRelease.set(())
        try await socialRaceDrain(scope, consumer: consumer)
        #expect(api.cancelEntered.entries.map(\.description) == [reason.description])
        #expect(api.completeEntered.entries.isEmpty)
        #expect(await ui.cancelCount == 1)
        #expect(await ui.returnedCount == 1) // Cancellation of the real UI task produced its callback.
    }

    @Test(arguments: SocialOperationCase.allCases)
    func `Social accepted cleanup retains operation after controller releases its owner`(_ testCase: SocialOperationCase) async throws {
        let scope = testTaskScope()
        defer { scope.shutdown() }
        let ui = SocialRaceUI()
        let api = SocialRaceAPIController(provider: testCase.provider)
        var runtime: SocialRaceRuntime? = try makeSocialRaceRuntime(testCase.provider, scope: scope, ui: ui, api: api)
        let consumer = try socialRaceConsumer(scope)
        let abort = try #require(runtime?.abort)
        let whenSettled = try #require(runtime?.whenSettled)
        let isRetained = try #require(runtime?.isRetained)
        runtime?.start()
        try await withOperationTimeout("Provider UI entered") { try await ui.started.waitUnlessCancelled() }
        runtime = nil
        let reason = Reason.systemError(details: "Owner released during cleanup")
        abort(reason)
        _ = try await api.cancelEntered.waitForCount(1, "Retained cleanup entered") { _ in true }
        #expect(try await withOperationTimeout("Owner release settlement") { try await whenSettled() } == "canceled:\(reason.description)")
        #expect(isRetained())
        await api.cancelRelease.set(())
        try await socialRaceDrain(scope, consumer: consumer)
        #expect(api.cancelFinished.entries.count == 1)
        #expect(await ui.cancelCount == 1)
    }

    @Test(arguments: SocialOperationCase.allCases)
    func `Social scope shutdown settles and drains active UI`(_ testCase: SocialOperationCase) async throws {
        let scope = testTaskScope()
        defer { scope.shutdown() }
        let ui = SocialRaceUI()
        let api = SocialRaceAPIController(provider: testCase.provider)
        let runtime = try makeSocialRaceRuntime(testCase.provider, scope: scope, ui: ui, api: api)
        runtime.start()
        try await withOperationTimeout("Provider UI entered") { try await ui.started.waitUnlessCancelled() }
        let tasks = try socialRaceTaskSnapshot(scope) // shutdown removes task handles from the scope.
        scope.shutdown()
        #expect(try await withOperationTimeout("Shutdown settles") { try await runtime.whenSettled() } == "canceled:\(Reason.systemError(details: "Operation canceled").description)")
        try await socialRaceJoin(tasks, "Shutdown producers drain")
        #expect(await ui.cancelCount == 1)
        #expect(api.cancelEntered.entries.isEmpty) // Scope shutdown does not promise remote cancellation.
    }
}

enum SocialFinishingOutcome: CaseIterable, Sendable {
    case tokenSuccess, tokenFailure, providerCanceled, providerFailed

    var usesToken: Bool { self == .tokenSuccess || self == .tokenFailure }
    var providerResult: SocialSignInResult {
        switch self {
        case .tokenSuccess, .tokenFailure: .success(id: "user", idToken: "token")
        case .providerCanceled: .canceled(reason: .userClose(details: "Provider dismissed"))
        case .providerFailed: .fail(error: .general("Provider failed"))
        }
    }
    var expected: String {
        switch self {
        case .tokenSuccess: "success"
        case .tokenFailure: "failure:Token completion failed"
        case .providerCanceled: "canceled:\(Reason.userClose(details: "Provider dismissed").description)"
        case .providerFailed: "failure:\(String(describing: SocialSignInResult.Error.general("Provider failed")))"
        }
    }
    var cancelReasons: [String] {
        switch self {
        case .tokenSuccess, .tokenFailure: []
        case .providerCanceled: [Reason.userClose(details: "Provider dismissed").description]
        case .providerFailed: [Reason.systemError(details: "Authorization failed").description]
        }
    }
}

private struct SocialRaceRuntime: Sendable {
    let start: @Sendable () -> Void
    let abort: @Sendable (Reason) -> Void
    let queuedTimeout: @Sendable () async -> Void
    let whenSettled: @Sendable () async throws -> String
    let isActive: @Sendable () async -> Bool
    let isRetained: @Sendable () -> Bool
}

private func makeSocialRaceRuntime(
    _ provider: SocialProviderID, scope: TaskScope, ui: SocialRaceUI,
    api: SocialRaceAPIController, startAPI: (any OIDCAPI)? = nil
) throws -> SocialRaceRuntime {
    let registry = OperationRegistryImpl(logger: nil)
    // Cancellation-aware observation keeps failure paths bounded; the controller still owns settlement.
    let settlement = CapturedValue<String>()
    switch provider {
    case .apple:
        let operation = SignInWithAppleOperationImpl(operationType: .oidcAuthenticationApple, operationRegistry: registry,
            ui: ui, api: startAPI ?? FakeOIDCAPI(startResult: .success(api)), taskScope: scope, context: nil, logger: nil)
        let controller = operation.controller
        let stream = try socialRaceStream(operation, event: SignInWithAppleOperationImpl.Event.self)
        return SocialRaceRuntime(start: {
                _ = operation.start()
                scope.spawn { await settlement.set(socialRaceOutcome(await controller.whenSettled())) }
            }, abort: { controller.abort(reason: $0) },
            queuedTimeout: { _ = await stream.yield(.abort(.timeout)) },
            whenSettled: { try await settlement.waitUnlessCancelled() }, isActive: {
                var iterator = await operation.stateStream().makeAsyncIterator()
                if case .active = await iterator.next() { return true }; return false
            }, isRetained: { [weak operation] in operation != nil })
    case .google:
        let operation = SignInWithGoogleOperationImpl(operationType: .oidcAuthenticationGoogle, operationRegistry: registry,
            ui: ui, api: startAPI ?? FakeOIDCAPI(startResult: .success(api)), taskScope: scope, context: nil, logger: nil)
        let controller = operation.controller
        let stream = try socialRaceStream(operation, event: SignInWithGoogleOperationImpl.Event.self)
        return SocialRaceRuntime(start: {
                _ = operation.start()
                scope.spawn { await settlement.set(socialRaceOutcome(await controller.whenSettled())) }
            }, abort: { controller.abort(reason: $0) },
            queuedTimeout: { _ = await stream.yield(.abort(.timeout)) },
            whenSettled: { try await settlement.waitUnlessCancelled() }, isActive: {
                var iterator = await operation.stateStream().makeAsyncIterator()
                if case .active = await iterator.next() { return true }; return false
            }, isRetained: { [weak operation] in operation != nil })
    }
}

private func socialRaceOutcome<Failure: OperationFailure>(
    _ result: OperationResult<AccessTokenWithUserInfo, Failure>
) -> String {
    switch result {
    case .success: "success"
    case .canceled(let reason): "canceled:\(reason.description)"
    case .failure(let failure): "failure:\(failure.message)"
    }
}

// A fired timer can have enqueued .abort(.timeout) before its task is cleared. Reflect only that
// ingress for a deterministic stale-timer test; provider and terminal events use their real producers.
private func socialRaceStream<Event: Sendable>(_ operation: Any, event: Event.Type) throws -> OperationEventStream<Event> {
    try #require(Mirror(reflecting: operation).children.first { $0.label == "stream" }?.value as? OperationEventStream<Event>)
}

// Intentional, isolated private-reflection seam: no production testing accessor or task API.
// These exact field names/types are a reviewed test dependency; read tasks under TaskScope.lock.
private func socialRaceTaskSnapshot(_ scope: TaskScope) throws -> [Task<Void, Never>] {
    let lock = try #require(Mirror(reflecting: scope).children.first { $0.label == "lock" }?.value as? NSLock)
    lock.lock()
    defer { lock.unlock() }
    let tasks = try #require(Mirror(reflecting: scope).children.first { $0.label == "tasks" }?.value as? [UUID: Task<Void, Never>])
    return Array(tasks.values)
}

private func socialRaceConsumer(_ scope: TaskScope) throws -> Task<Void, Never> {
    let tasks = try socialRaceTaskSnapshot(scope)
    try #require(tasks.count == 1, "Only the operation consumer exists before start")
    return try #require(tasks.first)
}

private func socialRaceJoin(_ tasks: [Task<Void, Never>], _ description: String) async throws {
    try await withOperationTimeout(description) {
        await withTaskCancellationHandler {
            for task in tasks { await task.value }
        } onCancel: {
            tasks.forEach { $0.cancel() }
        }
    }
}

private func socialRaceDrain(_ scope: TaskScope, consumer: Task<Void, Never>) async throws {
    try await socialRaceJoin([consumer], "Social event consumer drained")
    // After consumer completion no handler can spawn more cleanup. Join all remaining producers,
    // including not-yet-started UI cancellation, before asserting negative/exactly-once counts.
    try await socialRaceJoin(socialRaceTaskSnapshot(scope), "Social producers and cleanup drained")
}

private final class SocialRaceAPIController: OIDCAPIController, @unchecked Sendable {
    let challenge: SocialChallenge
    let provider: SocialProviderID
    let completeFailure: Bool
    let cancelEntered = AsyncSignalRecorder<Reason>()
    let cancelFinished = AsyncSignalRecorder<Void>()
    let completeEntered = AsyncSignalRecorder<String>()
    let cancelRelease = CapturedValue<Void>()
    let completeRelease = CapturedValue<Void>()
    init(provider: SocialProviderID, completeFailure: Bool = false) {
        self.provider = provider; self.completeFailure = completeFailure
        challenge = testSocialChallenge(provider: provider)
    }
    func cancel(reason: Reason) async -> APIResult<Void, OIDCCancelAPIFailure> {
        cancelEntered.append(reason)
        do {
            try await cancelRelease.waitUnlessCancelled()
            cancelFinished.append(())
            return .success(())
        } catch { return .canceled }
    }
    func completeWithToken(idToken: String) async -> APIResult<AccessTokenWithUserInfo, OIDCCompleteAPIFailure> {
        completeEntered.append(idToken)
        do {
            try await completeRelease.waitUnlessCancelled()
            return completeFailure ? .failure(.unexpected(errorCode: .unknown, message: "Token completion failed", underlyingError: SocialSignInResult.Error.general("Token completion failed"))) : .success(testSocialToken(provider: provider))
        } catch { return .canceled }
    }
    func completeWithCode(code: String) async -> APIResult<AccessTokenWithUserInfo, OIDCCompleteAPIFailure> { .canceled }
}

private final class SocialRaceStartAPI: OIDCAPI, @unchecked Sendable {
    let entered = AsyncSignalRecorder<Void>()
    let release = CapturedValue<Void>()
    let controller: any OIDCAPIController
    init(controller: any OIDCAPIController) { self.controller = controller }
    func start(params: OIDCAPIParams?) async -> APIResult<any OIDCAPIController, OIDCStartAPIFailure> {
        entered.append(())
        do { try await release.waitUnlessCancelled(); return .success(controller) }
        catch { return .canceled }
    }
}

@MainActor
private final class SocialRaceUI: SignInWithAppleUI, SignInWithGoogleUI, @unchecked Sendable {
    let started = MainActorCapturedValue<Void>()
    private let completion = MainActorCapturedValue<SocialSignInResult>()
    private(set) var cancelCount = 0
    private(set) var signInCount = 0
    private(set) var returnedCount = 0
    func signIn(clientID: String, nonce: String?) async -> SocialSignInResult {
        signInCount += 1
        started.set(())
        defer { returnedCount += 1 }
        do { return try await completion.waitUnlessCancelled() }
        catch { return .canceled(reason: .userClose(details: "UI canceled")) }
    }
    func finish(_ result: SocialSignInResult) { completion.set(result) }
    func cancel() { cancelCount += 1 }
}
