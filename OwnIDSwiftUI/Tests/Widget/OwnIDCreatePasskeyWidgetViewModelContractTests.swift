import OwnIDSwiftUI
import Testing
import UIKit

@_spi(OwnIDInternal) @testable import OwnIDCore

// Covers: UI-240, UI-260, UI-330, UI-380, UI-390, UI-400, UI-410, UI-420
@MainActor
@Suite(.serialized)
struct OwnIDCreatePasskeyWidgetViewModelContractTests {
    @Test(arguments: CreatePasskeyWidgetTerminalResult.allCases)
    func `Create passkey view model maps terminal flow results to effects`(
        terminalResult: CreatePasskeyWidgetTerminalResult
    ) async throws {
        let viewModel = makeCreatePasskeyViewModel { _, _ in ImmediateCreatePasskeyController(terminalResult.result) }

        startFlow(viewModel, loginID: "new@example.com")
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
        let viewModel = makeCreatePasskeyViewModel { _, _ in
            startCount += 1
            return ImmediateCreatePasskeyController(.success(.createPasskey(makeCreatePasskeyResponse())))
        }

        startFlow(viewModel, loginID: "first@example.com")
        startFlow(viewModel, loginID: "second@example.com")

        #expect(startCount == 1)
        #expect(viewModel.uiState == .init(isRunning: true, showCheckmark: false))
    }

    @Test func `Create passkey view model forwards abort to the active flow`() {
        let controller = RunningCreatePasskeyController()
        let viewModel = makeCreatePasskeyViewModel { _, _ in controller }

        viewModel.abort(reason: .timeout)
        #expect(controller.abortReasonDescriptions.isEmpty)

        startFlow(viewModel, loginID: "new@example.com")
        viewModel.abort(reason: .moveToOtherChallenge)

        #expect(controller.abortReasonDescriptions == ["moveToOtherChallenge"])
        #expect(viewModel.uiState == .init(isRunning: true, showCheckmark: false))
    }

    @Test func `Create passkey starter errors emit integration error and stop running`() async throws {
        let viewModel = makeCreatePasskeyViewModel { _, _ in
            throw WidgetStarterError("create passkey starter unavailable")
        }

        startFlow(viewModel, loginID: "new@example.com")
        let effect = try await nextElement(from: viewModel.uiEffects, "Expected create-passkey starter error effect")

        let error = try #require(createPasskeyError(from: effect), "Expected create-passkey starter error effect, got \(effect)")
        #expect(error.errorCode == .integrationError)
        #expect(error.message == "create passkey starter unavailable")
        #expect(viewModel.uiState == .init(isRunning: false, showCheckmark: false))
    }

    @Test func `Create passkey start forwards the exact hosting window to a custom starter`() async throws {
        let expectedWindow = makeWidgetTestWindow()
        defer { expectedWindow.close() }
        var receivedWindow: UIWindow?
        let viewModel = makeCreatePasskeyViewModel { window, _ in
            receivedWindow = window
            return ImmediateCreatePasskeyController(.success(.createPasskey(makeCreatePasskeyResponse())))
        }

        viewModel.startFlow(window: expectedWindow, loginID: "new@example.com")
        _ = try await nextElement(from: viewModel.uiEffects, "Expected create-passkey effect")

        #expect(receivedWindow === expectedWindow)
    }

    @Test func `Create passkey start without a hosting window reports an integration error without invoking the starter`() async throws {
        var startCount = 0
        let viewModel = makeCreatePasskeyViewModel { _, _ in
            startCount += 1
            return ImmediateCreatePasskeyController(.success(.createPasskey(makeCreatePasskeyResponse())))
        }

        viewModel.startFlow(window: nil, loginID: "new@example.com")
        let effect = try await nextElement(from: viewModel.uiEffects, "Expected missing-window create-passkey error")
        let error = try #require(createPasskeyError(from: effect))

        #expect(startCount == 0)
        #expect(error.errorCode == .integrationError)
        #expect(error.message.isEmpty == false)
        #expect(viewModel.uiState == .init(isRunning: false, showCheckmark: false))
    }

    @Test func `Create passkey completion reset and restore do not require a hosting window`() async throws {
        let viewModel = makeCreatePasskeyViewModel { _, _ in
            ImmediateCreatePasskeyController(.success(.createPasskey(makeCreatePasskeyResponse(id: "new@example.com"))))
        }
        let window = makeWidgetTestWindow()
        defer { window.close() }

        viewModel.startFlow(window: window, loginID: "new@example.com")
        _ = try await nextElement(from: viewModel.uiEffects, "Expected initial create-passkey effect")

        viewModel.startFlow(window: nil, loginID: "new@example.com")
        try #require(isResetRequested(try await nextElement(from: viewModel.uiEffects, "Expected reset effect")))

        viewModel.startFlow(window: nil, loginID: "new@example.com")
        let restored = try await nextElement(from: viewModel.uiEffects, "Expected restored create-passkey effect")
        let response = try #require(createPasskeyResponse(from: restored))
        #expect(response.loginID.id == "new@example.com")
    }

    @Test func `Deinitializing a running create-passkey view model aborts the flow and finishes its public streams`() async throws {
        let controller = RunningCreatePasskeyController()
        var viewModel: OwnIDCreatePasskeyWidgetViewModel? = makeCreatePasskeyViewModel { _, _ in controller }
        let weakViewModel = WeakObjectReference(viewModel)
        let window = makeWidgetTestWindow()
        defer { window.close() }
        viewModel!.startFlow(window: window, loginID: "new@example.com")

        var stateIterator = viewModel!.uiStateStream.makeAsyncIterator()
        #expect(await stateIterator.next() == .init(isRunning: true, showCheckmark: false))
        let effects = viewModel!.uiEffects

        viewModel = nil
        #expect(weakViewModel.value == nil)
        #expect(controller.abortReasonDescriptions == [Reason.userClose(details: "Create-passkey widget deinitialized").description])
        #expect(await stateIterator.next() == nil)
        #expect(try await nextOptionalElement(from: effects, "Expected create-passkey effects to finish") == nil)
    }

    @Test func `Create passkey effects are buffered until a subscriber is attached`() async throws {
        let viewModel = makeCreatePasskeyViewModel { _, _ in
            ImmediateCreatePasskeyController(.success(.createPasskey(makeCreatePasskeyResponse(id: "buffered@example.com"))))
        }

        startFlow(viewModel, loginID: "buffered@example.com")
        let effect = try await nextElement(from: viewModel.uiEffects, "Expected buffered create-passkey effect")

        let response = try #require(createPasskeyResponse(from: effect), "Expected buffered create-passkey effect, got \(effect)")
        #expect(response.loginID.id == "buffered@example.com")
        #expect(viewModel.uiState == .init(isRunning: false, showCheckmark: true))
    }

    @Test func `Create passkey start clears and restores remembered completion without restarting`() async throws {
        var startCount = 0
        let viewModel = makeCreatePasskeyViewModel { _, _ in
            startCount += 1
            return ImmediateCreatePasskeyController(.success(.createPasskey(makeCreatePasskeyResponse(id: "new@example.com"))))
        }

        startFlow(viewModel, loginID: "new@example.com")
        let initialEffect = try await nextElement(from: viewModel.uiEffects, "Expected initial create-passkey effect")
        let initialResponse = try #require(
            createPasskeyResponse(from: initialEffect),
            "Expected initial create-passkey effect, got \(initialEffect)"
        )
        #expect(initialResponse.loginID.id == "new@example.com")
        #expect(viewModel.uiState == .init(isRunning: false, showCheckmark: true))

        startFlow(viewModel, loginID: "new@example.com")
        let resetEffect = try await nextElement(from: viewModel.uiEffects, "Expected reset before clearing remembered completion")
        try #require(isResetRequested(resetEffect), "Expected reset effect, got \(resetEffect)")
        #expect(viewModel.uiState == .init(isRunning: false, showCheckmark: false))

        startFlow(viewModel, loginID: " new@example.com ")
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
        let viewModel = makeCreatePasskeyViewModel { _, _ in
            ImmediateCreatePasskeyController(.success(.createPasskey(makeCreatePasskeyResponse(id: "latest@example.com"))))
        }

        let firstEffects = viewModel.uiEffects
        let secondEffects = viewModel.uiEffects

        let firstValue = try await nextOptionalElement(
            from: firstEffects,
            "Expected previous create-passkey effect subscriber to finish"
        )
        #expect(firstValue == nil)

        startFlow(viewModel, loginID: "latest@example.com")
        let effect = try await nextElement(from: secondEffects, "Expected the latest subscriber to receive the effect")

        let response = try #require(
            createPasskeyResponse(from: effect),
            "Expected create-passkey effect for latest subscriber, got \(effect)"
        )
        #expect(response.loginID.id == "latest@example.com")
    }

    @Test func `Create passkey completion is in memory and login ID scoped`() async throws {
        let response = makeCreatePasskeyResponse(id: "new@example.com")
        let viewModel = makeCreatePasskeyViewModel { _, _ in
            ImmediateCreatePasskeyController(.success(.createPasskey(response)))
        }

        startFlow(viewModel, loginID: "new@example.com")
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

    @Test func `Login ID edits while running do not clear terminal create-passkey completion`() async throws {
        let controller = DeferredCreatePasskeyController()
        let viewModel = makeCreatePasskeyViewModel { _, _ in controller }
        let effects = viewModel.uiEffects
        let window = makeWidgetTestWindow()
        defer { window.close() }

        viewModel.startFlow(window: window, loginID: "initial@example.com")
        #expect(viewModel.uiState == .init(isRunning: true, showCheckmark: false))

        viewModel.onLoginIDChanged("edited@example.com")
        #expect(viewModel.uiState == .init(isRunning: true, showCheckmark: false))

        await controller.settle(
            .success(.createPasskey(makeCreatePasskeyResponse(id: "created@example.com")))
        )
        let effect = try await nextElement(from: effects, "Expected terminal create-passkey effect")
        let response = try #require(createPasskeyResponse(from: effect), "Expected create-passkey effect, got \(effect)")

        #expect(response.loginID.id == "created@example.com")
        #expect(viewModel.uiState == .init(isRunning: false, showCheckmark: true))
    }

    @Test(arguments: WidgetLoginIDCase.createPasskeyNormalizationCases)
    func `Create passkey flow normalizes login IDs and uses widget button source`(input: WidgetLoginIDCase) throws {
        var capturedContext: BoostFlowContext?
        let viewModel = makeCreatePasskeyViewModel { _, context in
            capturedContext = context
            return ImmediateCreatePasskeyController(.success(.createPasskey(makeCreatePasskeyResponse())))
        }

        startFlow(viewModel, loginID: input.raw)

        try expectWidgetContext(capturedContext, normalizedLoginID: input.normalized)
    }
}
