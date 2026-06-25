import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

struct EliteFlowImplWebBridgeSettlementTests {

    @Test func `Elite maps WebBridge success once`() async throws {
        let harness = EliteFlowHarness()
        let controller = harness.flow.start(.empty)
        let webBridgeController = try await harness.startedWebBridgeController()

        harness.webBridge.settle(.success(()))
        let result = try await harness.flowResult(controller, "elite success")

        try requireSuccess(result)
        let cached = await controller.whenSettled()
        try requireSuccess(cached)

        harness.webBridge.settle(.canceled(.userClose(details: "late cancel")))
        controller.abort(reason: .systemError(details: "late abort"))
        let afterLateEvents = await controller.whenSettled()
        try requireSuccess(afterLateEvents)

        #expect(harness.userJourney.completedOutcomes.get().count == 1)
        #expect(webBridgeController.operationID == harness.webBridge.operationID)
    }

    @Test func `Elite maps WebBridge failure once as operation failure`() async throws {
        let harness = EliteFlowHarness()
        let controller = harness.flow.start(.empty)
        let webBridgeController = try await harness.startedWebBridgeController()

        let webBridgeFailure = WebBridgeOperationFailure.ui(
            .init(errorCode: .unknown, message: "Fake WebBridge UI failed")
        )
        harness.webBridge.settle(.failure(webBridgeFailure))
        let result = try await harness.flowResult(controller, "elite failure")

        let failure = try requireFailure(result)
        guard case .operationFailed(let operationType, let errorCode, let message, let operationID, let operationFailure, _) = failure
        else {
            _ = try #require(nil as Void?, "Expected operationFailed, got \(failure)")
            return
        }
        #expect(operationType == .webBridge)
        #expect(errorCode == .unknown)
        #expect(message == "Elite operation failed: Fake WebBridge UI failed")
        #expect(operationID == webBridgeController.operationID)
        #expect(operationFailure?.message == webBridgeFailure.message)

        harness.webBridge.settle(.success(()))
        controller.abort(reason: .userClose(details: "late abort"))
        let afterLateEvents = await controller.whenSettled()
        let cachedFailure = try requireFailure(afterLateEvents)
        #expect(cachedFailure.message == failure.message)
        #expect(harness.userJourney.completedOutcomes.get().count == 1)
    }

    @Test func `Elite maps WebBridge cancellation once and preserves reason`() async throws {
        let harness = EliteFlowHarness()
        let controller = harness.flow.start(.empty)
        _ = try await harness.startedWebBridgeController()

        let expectedReason = Reason.userClose(details: "host canceled")
        harness.webBridge.settle(.canceled(expectedReason))
        let result = try await harness.flowResult(controller, "elite cancellation")

        let reason = try requireCancellation(result)
        #expect(reason.description == expectedReason.description)

        harness.webBridge.settle(.failure(.unexpected(message: "late failure")))
        controller.abort(reason: .systemError(details: "late abort"))
        let afterLateEvents = await controller.whenSettled()
        let cachedReason = try requireCancellation(afterLateEvents)
        #expect(cachedReason.description == expectedReason.description)
        #expect(harness.userJourney.completedOutcomes.get().count == 1)
    }

    @Test func `Elite abort forwards to active WebBridge controller and settles with expected reason`() async throws {
        let harness = EliteFlowHarness()
        let controller = harness.flow.start(.empty)
        _ = try await harness.startedWebBridgeController()

        let expectedReason = Reason.systemError(details: "owner dismissed")
        controller.abort(reason: expectedReason)

        let result = try await harness.flowResult(controller, "elite abort")
        let reason = try requireCancellation(result)

        #expect(reason.description == expectedReason.description)
        let forwardedReason = try #require(harness.webBridge.abortReasons.get().first)
        #expect(forwardedReason.description == expectedReason.description)
        #expect(harness.userJourney.completedOutcomes.get().count == 1)
    }
}

private struct EliteFlowHarness {
    let webBridge: ControlledWebBridgeOperation
    let userJourney: RecordingUserJourney
    let flow: EliteFlowImpl

    init() {
        self.webBridge = ControlledWebBridgeOperation()
        self.userJourney = RecordingUserJourney()
        self.flow = EliteFlowImpl(
            webBridgeOperation: webBridge,
            userJourney: userJourney,
            taskScope: flowTaskScope(),
            logger: nil
        )
    }

    func startedWebBridgeController() async throws -> WebBridgeOperationControllerImpl {
        try await withFlowTimeout("webBridge start") {
            await webBridge.startedController.wait()
        }
    }

    func flowResult(
        _ controller: any EliteFlowController,
        _ description: String
    ) async throws -> FlowResult<Void, EliteFlowFailure> {
        try await withFlowTimeout(description) {
            await controller.whenSettled()
        }
    }
}

private final class ControlledWebBridgeOperation: WebBridgeOperation, @unchecked Sendable {
    let operationType: OperationType = .webBridge
    let operationID = OperationID(type: .webBridge, id: "web-bridge-flow-test")
    let startParams = FlowLocked<[WebBridgeOperationParams?]>([])
    let abortReasons = FlowLocked<[Reason]>([])
    let startedController = CapturedFlowValue<WebBridgeOperationControllerImpl>()

    private lazy var controller = WebBridgeOperationControllerImpl(operationID: operationID) { [abortReasons] reason in
        abortReasons.mutate { $0.append(reason) }
    }

    func availability(params: (any CapabilityParams)?) async -> Availability {
        .available
    }

    func start(params: WebBridgeOperationParams?) -> any OperationController<Void, WebBridgeOperationFailure> {
        startParams.mutate { $0.append(params) }
        let controller = controller
        startedController.set(controller)
        return controller
    }

    func settle(_ result: OperationResult<Void, WebBridgeOperationFailure>) {
        switch result {
        case .success:
            controller.complete(())
        case .canceled(let reason):
            controller.cancel(reason)
        case .failure(let failure):
            controller.fail(failure)
        }
    }
}

private final class RecordingUserJourney: UserJourney, @unchecked Sendable {
    let startedFlows = FlowLocked<[String?]>([])
    let referers = FlowLocked<[String]>([])
    let completedOutcomes = FlowLocked<[UserJourneyOutcome]>([])

    func startFlow(name: String?, source: FlowInfo.Source, traceParent: String?) async {
        startedFlows.mutate { $0.append(name) }
    }

    func switchToFlow(flowID: String?, name: String?, source: FlowInfo.Source) async {}

    func setUserInfo(_ loginID: LoginID) async {}

    func setReferer(_ referer: String) async {
        referers.mutate { $0.append(referer) }
    }

    func startOperation(operationID: OperationID) async {}

    func addOperationClick(operationID: OperationID) async {}

    func completeOperation(operationID: OperationID, errorCode: ErrorCode?, source: String?, message: String?) async {}

    nonisolated func completeFlow(_ outcome: UserJourneyOutcome) {
        completedOutcomes.mutate { $0.append(outcome) }
    }
}
