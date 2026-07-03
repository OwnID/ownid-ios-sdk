import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

struct RecordedUserJourneyFlow: Sendable, Equatable {
    let name: String?
    let source: FlowInfo.Source
    let traceParent: String?
    let flowID: String?

    init(name: String?, source: FlowInfo.Source, traceParent: String?, flowID: String? = nil) {
        self.name = name
        self.source = source
        self.traceParent = traceParent
        self.flowID = flowID
    }
}

struct RecordedUserJourneyOperationCompletion: Sendable, Equatable {
    let operationID: OperationID
    let errorCode: ErrorCode?
    let source: String?
    let message: String?
}

final class RecordingFlowUserJourney: UserJourney, @unchecked Sendable {
    let startedFlows = FlowLocked<[RecordedUserJourneyFlow]>([])
    let switchedFlows = FlowLocked<[RecordedUserJourneyFlow]>([])
    let userInfo = FlowLocked<[LoginID]>([])
    let referers = FlowLocked<[String]>([])
    let startedOperations = FlowLocked<[OperationID]>([])
    let operationClicks = FlowLocked<[OperationID]>([])
    let completedOperations = FlowLocked<[RecordedUserJourneyOperationCompletion]>([])
    let completedOutcomes = FlowLocked<[UserJourneyOutcome]>([])

    func startFlow(name: String?, source: FlowInfo.Source, traceParent: String?) async {
        startedFlows.mutate { $0.append(RecordedUserJourneyFlow(name: name, source: source, traceParent: traceParent)) }
    }

    func switchToFlow(flowID: String?, name: String?, source: FlowInfo.Source) async {
        switchedFlows.mutate { $0.append(RecordedUserJourneyFlow(name: name, source: source, traceParent: nil, flowID: flowID)) }
    }

    func setUserInfo(_ loginID: LoginID) async {
        userInfo.mutate { $0.append(loginID) }
    }

    func setReferer(_ referer: String) async {
        referers.mutate { $0.append(referer) }
    }

    func startOperation(operationID: OperationID) async {
        startedOperations.mutate { $0.append(operationID) }
    }

    func addOperationClick(operationID: OperationID) async {
        operationClicks.mutate { $0.append(operationID) }
    }

    func completeOperation(operationID: OperationID, errorCode: ErrorCode?, source: String?, message: String?) async {
        completedOperations.mutate {
            $0.append(
                RecordedUserJourneyOperationCompletion(
                    operationID: operationID,
                    errorCode: errorCode,
                    source: source,
                    message: message
                )
            )
        }
    }

    nonisolated func completeFlow(_ outcome: UserJourneyOutcome) {
        completedOutcomes.mutate { $0.append(outcome) }
    }
}

func requireCompletedJourneyOutcome(
    _ outcomes: [UserJourneyOutcome],
    authMethod: AuthMethod? = nil,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws {
    let outcome = try #require(outcomes.first, "Expected completed journey outcome", sourceLocation: sourceLocation)
    guard case .completed(let actualAuthMethod) = outcome else {
        _ = try #require(nil as Void?, "Expected completed journey outcome, got \(outcome)", sourceLocation: sourceLocation)
        return
    }
    #expect(outcomes.count == 1, sourceLocation: sourceLocation)
    #expect(actualAuthMethod == authMethod, sourceLocation: sourceLocation)
}

func requireErrorJourneyOutcome(
    _ outcomes: [UserJourneyOutcome],
    errorCode: ErrorCode,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws -> (source: String?, message: String?) {
    let outcome = try #require(outcomes.first, "Expected error journey outcome", sourceLocation: sourceLocation)
    guard case .error(let actualErrorCode, let source, let message) = outcome else {
        return try #require(nil as (String?, String?)?, "Expected error journey outcome, got \(outcome)", sourceLocation: sourceLocation)
    }
    #expect(outcomes.count == 1, sourceLocation: sourceLocation)
    #expect(actualErrorCode == errorCode, sourceLocation: sourceLocation)
    return (source, message)
}

func requireOperationCompletion(
    _ completions: [RecordedUserJourneyOperationCompletion],
    operationID: OperationID,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws -> RecordedUserJourneyOperationCompletion {
    let completion = try #require(
        completions.first { $0.operationID == operationID },
        "Expected operation completion for \(operationID)",
        sourceLocation: sourceLocation
    )
    #expect(completions.count == 1, sourceLocation: sourceLocation)
    return completion
}
