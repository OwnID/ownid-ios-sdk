import OwnIDSwiftUI
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

@MainActor
@Suite(.serialized)
struct OwnIDLoginWidgetViewModelContractTests {
    @Test(arguments: LoginWidgetTerminalResult.allCases)
    func `Login view model maps terminal flow results to effects`(terminalResult: LoginWidgetTerminalResult) async throws {
        let viewModel = makeLoginViewModel { _ in ImmediateLoginController(terminalResult.result) }

        viewModel.startFlow(loginID: "user@example.com")
        let effect = try await nextElement(from: viewModel.uiEffects, "Expected a terminal login effect")

        switch terminalResult {
        case .success:
            let response = try #require(loginResponse(from: effect), "Expected login effect")
            #expect(response.loginID.id == "user@example.com")
        case .canceled:
            let reason = try #require(cancellationReason(from: effect), "Expected cancellation effect")
            #expect(reason.description == Reason.userClose(details: "dismissed").description)
        case .failure:
            let error = try #require(loginError(from: effect), "Expected login error effect")
            #expect(error.errorCode == .integrationError)
            #expect(error.message == "login failed")
        }

        let state = try await nextElement(from: viewModel.uiStateStream, "Expected latest login UI state")
        #expect(state == .init(isRunning: false))
    }

    @Test func `Login view model ignores repeated starts while running`() {
        var startCount = 0
        let viewModel = makeLoginViewModel { _ in
            startCount += 1
            return ImmediateLoginController(.success(makeLoginResponse()))
        }

        viewModel.startFlow(loginID: "first@example.com")
        viewModel.startFlow(loginID: "second@example.com")

        #expect(startCount == 1)
        #expect(viewModel.uiState == .init(isRunning: true))
    }

    @Test func `Login view model forwards abort to the active flow`() {
        let controller = RunningLoginController()
        let viewModel = makeLoginViewModel { _ in controller }

        viewModel.abort(reason: .timeout)
        #expect(controller.abortReasonDescriptions.isEmpty)

        viewModel.startFlow(loginID: "user@example.com")
        viewModel.abort(reason: .systemError(details: "screen dismissed"))

        #expect(controller.abortReasonDescriptions == ["systemError: screen dismissed"])
        #expect(viewModel.uiState == .init(isRunning: true))
    }

    @Test func `Login starter errors emit integration error and stop running`() async throws {
        let viewModel = makeLoginViewModel { _ in
            throw WidgetStarterError("login starter unavailable")
        }

        viewModel.startFlow(loginID: "user@example.com")
        let effect = try await nextElement(from: viewModel.uiEffects, "Expected login starter error effect")

        let error = try #require(loginError(from: effect), "Expected login starter error effect, got \(effect)")
        #expect(error.errorCode == .integrationError)
        #expect(error.message == "login starter unavailable")
        #expect(viewModel.uiState == .init(isRunning: false))
    }

    @Test func `Login effects are buffered until a subscriber is attached`() async throws {
        let viewModel = makeLoginViewModel { _ in
            ImmediateLoginController(.success(makeLoginResponse(id: "buffered@example.com")))
        }

        viewModel.startFlow(loginID: "buffered@example.com")
        let effect = try await nextElement(from: viewModel.uiEffects, "Expected buffered login effect")

        let response = try #require(loginResponse(from: effect), "Expected buffered login effect, got \(effect)")
        #expect(response.loginID.id == "buffered@example.com")
    }

    @Test func `Login effects keep only the latest subscriber active`() async throws {
        let viewModel = makeLoginViewModel { _ in
            ImmediateLoginController(.success(makeLoginResponse(id: "latest@example.com")))
        }

        let firstEffects = viewModel.uiEffects
        let secondEffects = viewModel.uiEffects

        let firstValue = try await nextOptionalElement(
            from: firstEffects,
            "Expected previous login effect subscriber to finish"
        )
        #expect(firstValue == nil)

        viewModel.startFlow(loginID: "latest@example.com")
        let effect = try await nextElement(from: secondEffects, "Expected the latest subscriber to receive the effect")

        let response = try #require(loginResponse(from: effect), "Expected login effect for latest subscriber, got \(effect)")
        #expect(response.loginID.id == "latest@example.com")
    }

    @Test(arguments: WidgetLoginIDCase.loginNormalizationCases)
    func `Login flow normalizes login IDs and uses widget button source`(input: WidgetLoginIDCase) throws {
        var capturedContext: BoostFlowContext?
        let viewModel = makeLoginViewModel { context in
            capturedContext = context
            return ImmediateLoginController(.success(makeLoginResponse()))
        }

        viewModel.startFlow(loginID: input.raw)

        try expectWidgetContext(capturedContext, normalizedLoginID: input.normalized)
    }
}
