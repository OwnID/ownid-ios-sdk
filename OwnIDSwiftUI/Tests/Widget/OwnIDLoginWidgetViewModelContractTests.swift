import OwnIDSwiftUI
import Testing
import UIKit

@_spi(OwnIDInternal) @testable import OwnIDCore

@MainActor
@Suite(.serialized)
// Covers: UI-170, UI-190, UI-320, UI-340, UI-350, UI-360, UI-370
struct OwnIDLoginWidgetViewModelContractTests {
    @Test(arguments: LoginWidgetTerminalResult.allCases)
    func `Login view model maps terminal flow results to effects`(terminalResult: LoginWidgetTerminalResult) async throws {
        let viewModel = makeLoginViewModel { _, _ in ImmediateLoginController(terminalResult.result) }

        startFlow(viewModel, loginID: "user@example.com")
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
        let viewModel = makeLoginViewModel { _, _ in
            startCount += 1
            return ImmediateLoginController(.success(makeLoginResponse()))
        }

        startFlow(viewModel, loginID: "first@example.com")
        startFlow(viewModel, loginID: "second@example.com")

        #expect(startCount == 1)
        #expect(viewModel.uiState == .init(isRunning: true))
    }

    @Test func `Login view model forwards abort to the active flow`() {
        let controller = RunningLoginController()
        let viewModel = makeLoginViewModel { _, _ in controller }

        viewModel.abort(reason: .timeout)
        #expect(controller.abortReasonDescriptions.isEmpty)

        startFlow(viewModel, loginID: "user@example.com")
        viewModel.abort(reason: .systemError(details: "screen dismissed"))

        #expect(controller.abortReasonDescriptions == ["systemError: screen dismissed"])
        #expect(viewModel.uiState == .init(isRunning: true))
    }

    @Test func `Login starter errors emit integration error and stop running`() async throws {
        let viewModel = makeLoginViewModel { _, _ in
            throw WidgetStarterError("login starter unavailable")
        }

        startFlow(viewModel, loginID: "user@example.com")
        let effect = try await nextElement(from: viewModel.uiEffects, "Expected login starter error effect")

        let error = try #require(loginError(from: effect), "Expected login starter error effect, got \(effect)")
        #expect(error.errorCode == .integrationError)
        #expect(error.message == "login starter unavailable")
        #expect(viewModel.uiState == .init(isRunning: false))
    }

    @Test func `Login start forwards the exact hosting window to a custom starter`() async throws {
        let expectedWindow = makeWidgetTestWindow()
        defer { expectedWindow.close() }
        var receivedWindow: UIWindow?
        let viewModel = makeLoginViewModel { window, _ in
            receivedWindow = window
            return ImmediateLoginController(.success(makeLoginResponse()))
        }

        viewModel.startFlow(window: expectedWindow, loginID: "user@example.com")
        _ = try await nextElement(from: viewModel.uiEffects, "Expected login effect")

        #expect(receivedWindow === expectedWindow)
    }

    @Test func `Login start without a hosting window reports an integration error without invoking the starter`() async throws {
        var startCount = 0
        let viewModel = makeLoginViewModel { _, _ in
            startCount += 1
            return ImmediateLoginController(.success(makeLoginResponse()))
        }

        viewModel.startFlow(window: nil, loginID: "user@example.com")
        let effect = try await nextElement(from: viewModel.uiEffects, "Expected missing-window login error")
        let error = try #require(loginError(from: effect))

        #expect(startCount == 0)
        #expect(error.errorCode == .integrationError)
        #expect(error.message.isEmpty == false)
        #expect(viewModel.uiState == .init(isRunning: false))
    }

    @Test func `Deinitializing a running login view model aborts the flow and finishes its public streams`() async throws {
        let controller = RunningLoginController()
        var viewModel: OwnIDLoginWidgetViewModel? = makeLoginViewModel { _, _ in controller }
        let weakViewModel = WeakObjectReference(viewModel)
        let window = makeWidgetTestWindow()
        defer { window.close() }
        viewModel!.startFlow(window: window, loginID: "user@example.com")

        var stateIterator = viewModel!.uiStateStream.makeAsyncIterator()
        #expect(await stateIterator.next() == .init(isRunning: true))
        let effects = viewModel!.uiEffects

        viewModel = nil
        #expect(weakViewModel.value == nil)
        #expect(controller.abortReasonDescriptions == [Reason.userClose(details: "Login widget deinitialized").description])
        #expect(await stateIterator.next() == nil)
        #expect(try await nextOptionalElement(from: effects, "Expected login effects to finish") == nil)
    }

    @Test func `Login effects are buffered until a subscriber is attached`() async throws {
        let viewModel = makeLoginViewModel { _, _ in
            ImmediateLoginController(.success(makeLoginResponse(id: "buffered@example.com")))
        }

        startFlow(viewModel, loginID: "buffered@example.com")
        let effect = try await nextElement(from: viewModel.uiEffects, "Expected buffered login effect")

        let response = try #require(loginResponse(from: effect), "Expected buffered login effect, got \(effect)")
        #expect(response.loginID.id == "buffered@example.com")
    }

    @Test func `Login effects keep only the latest subscriber active`() async throws {
        let viewModel = makeLoginViewModel { _, _ in
            ImmediateLoginController(.success(makeLoginResponse(id: "latest@example.com")))
        }

        let firstEffects = viewModel.uiEffects
        let secondEffects = viewModel.uiEffects

        let firstValue = try await nextOptionalElement(
            from: firstEffects,
            "Expected previous login effect subscriber to finish"
        )
        #expect(firstValue == nil)

        startFlow(viewModel, loginID: "latest@example.com")
        let effect = try await nextElement(from: secondEffects, "Expected the latest subscriber to receive the effect")

        let response = try #require(loginResponse(from: effect), "Expected login effect for latest subscriber, got \(effect)")
        #expect(response.loginID.id == "latest@example.com")
    }

    @Test(arguments: WidgetLoginIDCase.loginNormalizationCases)
    func `Login flow normalizes login IDs and uses widget button source`(input: WidgetLoginIDCase) throws {
        var capturedContext: BoostFlowContext?
        let viewModel = makeLoginViewModel { _, context in
            capturedContext = context
            return ImmediateLoginController(.success(makeLoginResponse()))
        }

        startFlow(viewModel, loginID: input.raw)

        try expectWidgetContext(capturedContext, normalizedLoginID: input.normalized)
    }
}
