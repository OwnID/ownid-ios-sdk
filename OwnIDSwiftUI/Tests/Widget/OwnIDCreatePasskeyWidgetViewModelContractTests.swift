import OwnIDSwiftUI
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

@MainActor
@Suite(.serialized)
struct OwnIDCreatePasskeyWidgetViewModelContractTests {
    @Test(arguments: CreatePasskeyWidgetTerminalResult.allCases)
    func `Create passkey view model maps terminal flow results to effects`(
        terminalResult: CreatePasskeyWidgetTerminalResult
    ) async throws {
        let viewModel = makeCreatePasskeyViewModel { _ in ImmediateCreatePasskeyController(terminalResult.result) }

        viewModel.startFlow(loginID: "new@example.com")
        let effect = try await nextElement(from: viewModel.uiEffects, "Expected a terminal create-passkey effect")

        switch terminalResult {
        case .login:
            let response = try #require(loginResponse(from: effect), "Expected login effect")
            #expect(response.loginID.id == "existing@example.com")
            #expect(viewModel.uiState == .init(isRunning: false, showCheckmark: false))
        case .createPasskey:
            let response = try #require(createPasskeyResponse(from: effect), "Expected create-passkey effect")
            #expect(response.loginID.id == "new@example.com")
            #expect(viewModel.uiState == .init(isRunning: false, showCheckmark: true))
        case .canceled:
            let reason = try #require(cancellationReason(from: effect), "Expected cancellation effect")
            #expect(reason.description == Reason.userClose(details: "dismissed").description)
            #expect(viewModel.uiState == .init(isRunning: false, showCheckmark: false))
        case .failure:
            let error = try #require(createPasskeyError(from: effect), "Expected create-passkey error effect")
            #expect(error.errorCode == .integrationError)
            #expect(error.message == "create passkey failed")
            #expect(viewModel.uiState == .init(isRunning: false, showCheckmark: false))
        }
    }

    @Test func `Create passkey view model ignores repeated starts while running`() {
        var startCount = 0
        let viewModel = makeCreatePasskeyViewModel { _ in
            startCount += 1
            return ImmediateCreatePasskeyController(.success(.createPasskey(makeCreatePasskeyResponse())))
        }

        viewModel.startFlow(loginID: "first@example.com")
        viewModel.startFlow(loginID: "second@example.com")

        #expect(startCount == 1)
        #expect(viewModel.uiState == .init(isRunning: true, showCheckmark: false))
    }

    @Test func `Create passkey view model forwards abort to the active flow`() {
        let controller = RunningCreatePasskeyController()
        let viewModel = makeCreatePasskeyViewModel { _ in controller }

        viewModel.abort(reason: .timeout)
        #expect(controller.abortReasonDescriptions.isEmpty)

        viewModel.startFlow(loginID: "new@example.com")
        viewModel.abort(reason: .moveToOtherChallenge)

        #expect(controller.abortReasonDescriptions == ["moveToOtherChallenge"])
        #expect(viewModel.uiState == .init(isRunning: true, showCheckmark: false))
    }

    @Test func `Create passkey effects are buffered until a subscriber is attached`() async throws {
        let viewModel = makeCreatePasskeyViewModel { _ in
            ImmediateCreatePasskeyController(.success(.createPasskey(makeCreatePasskeyResponse(id: "buffered@example.com"))))
        }

        viewModel.startFlow(loginID: "buffered@example.com")
        let effect = try await nextElement(from: viewModel.uiEffects, "Expected buffered create-passkey effect")

        let response = try #require(createPasskeyResponse(from: effect), "Expected buffered create-passkey effect, got \(effect)")
        #expect(response.loginID.id == "buffered@example.com")
        #expect(viewModel.uiState == .init(isRunning: false, showCheckmark: true))
    }

    @Test func `Create passkey start clears and restores remembered completion without restarting`() async throws {
        var startCount = 0
        let viewModel = makeCreatePasskeyViewModel { _ in
            startCount += 1
            return ImmediateCreatePasskeyController(.success(.createPasskey(makeCreatePasskeyResponse(id: "new@example.com"))))
        }

        viewModel.startFlow(loginID: "new@example.com")
        let initialEffect = try await nextElement(from: viewModel.uiEffects, "Expected initial create-passkey effect")
        let initialResponse = try #require(
            createPasskeyResponse(from: initialEffect),
            "Expected initial create-passkey effect, got \(initialEffect)"
        )
        #expect(initialResponse.loginID.id == "new@example.com")
        #expect(viewModel.uiState == .init(isRunning: false, showCheckmark: true))

        viewModel.startFlow(loginID: "new@example.com")
        let resetEffect = try await nextElement(from: viewModel.uiEffects, "Expected reset before clearing remembered completion")
        try #require(isResetRequested(resetEffect), "Expected reset effect, got \(resetEffect)")
        #expect(viewModel.uiState == .init(isRunning: false, showCheckmark: false))

        viewModel.startFlow(loginID: " new@example.com ")
        let restoredEffect = try await nextElement(from: viewModel.uiEffects, "Expected remembered create-passkey effect")
        let restoredResponse = try #require(
            createPasskeyResponse(from: restoredEffect),
            "Expected restored create-passkey effect, got \(restoredEffect)"
        )
        #expect(restoredResponse.loginID.id == "new@example.com")
        #expect(viewModel.uiState == .init(isRunning: false, showCheckmark: true))
        #expect(startCount == 1)
    }

    @Test func `Create passkey effects keep only the latest subscriber active`() async throws {
        let viewModel = makeCreatePasskeyViewModel { _ in
            ImmediateCreatePasskeyController(.success(.createPasskey(makeCreatePasskeyResponse(id: "latest@example.com"))))
        }

        let firstEffects = viewModel.uiEffects
        let secondEffects = viewModel.uiEffects

        let firstValue = try await nextOptionalElement(
            from: firstEffects,
            "Expected previous create-passkey effect subscriber to finish"
        )
        #expect(firstValue == nil)

        viewModel.startFlow(loginID: "latest@example.com")
        let effect = try await nextElement(from: secondEffects, "Expected the latest subscriber to receive the effect")

        let response = try #require(
            createPasskeyResponse(from: effect),
            "Expected create-passkey effect for latest subscriber, got \(effect)"
        )
        #expect(response.loginID.id == "latest@example.com")
    }

    @Test func `Create passkey completion is in memory and login ID scoped`() async throws {
        let response = makeCreatePasskeyResponse(id: "new@example.com")
        let viewModel = makeCreatePasskeyViewModel { _ in
            ImmediateCreatePasskeyController(.success(.createPasskey(response)))
        }

        viewModel.startFlow(loginID: "new@example.com")
        let createdEffect = try await nextElement(from: viewModel.uiEffects, "Expected initial create-passkey effect")
        let createdResponse = try #require(
            createPasskeyResponse(from: createdEffect),
            "Expected initial create-passkey effect, got \(createdEffect)"
        )
        #expect(createdResponse.loginID.id == "new@example.com")
        #expect(viewModel.uiState == .init(isRunning: false, showCheckmark: true))

        viewModel.onLoginIDChanged("other@example.com")
        let resetEffect = try await nextElement(from: viewModel.uiEffects, "Expected reset when login ID changes")
        try #require(isResetRequested(resetEffect), "Expected reset effect, got \(resetEffect)")
        #expect(viewModel.uiState == .init(isRunning: false, showCheckmark: false))

        viewModel.onLoginIDChanged(" new@example.com ")
        let restoredEffect = try await nextElement(from: viewModel.uiEffects, "Expected restored create-passkey effect")
        let restoredResponse = try #require(
            createPasskeyResponse(from: restoredEffect),
            "Expected restored create-passkey effect, got \(restoredEffect)"
        )
        #expect(restoredResponse.loginID.id == "new@example.com")
        #expect(viewModel.uiState == .init(isRunning: false, showCheckmark: true))
    }

    @Test(arguments: WidgetLoginIDCase.createPasskeyNormalizationCases)
    func `Create passkey flow normalizes login IDs and uses widget button source`(input: WidgetLoginIDCase) throws {
        var capturedContext: BoostFlowContext?
        let viewModel = makeCreatePasskeyViewModel { context in
            capturedContext = context
            return ImmediateCreatePasskeyController(.success(.createPasskey(makeCreatePasskeyResponse())))
        }

        viewModel.startFlow(loginID: input.raw)

        try expectWidgetContext(capturedContext, normalizedLoginID: input.normalized)
    }
}
