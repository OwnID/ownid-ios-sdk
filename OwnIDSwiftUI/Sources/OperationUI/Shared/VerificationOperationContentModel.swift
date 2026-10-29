import Combine
import Foundation

@MainActor
internal final class VerificationOperationContentModel<OperationState: Sendable, Strings: Sendable>: ObservableObject {
    @Published internal var operationState: OperationState
    @Published internal var resolvedStrings: Strings?

    private let makeStateStream: @MainActor () -> AsyncStream<OperationState>
    private let makeStringsStream: @MainActor () -> AsyncStream<Strings?>
    private let shouldFinishStateObservation: @MainActor (OperationState) -> Bool
    private var observationGeneration = 0

    internal init(
        initialState: OperationState,
        makeStateStream: @escaping @MainActor () -> AsyncStream<OperationState>,
        makeStringsStream: @escaping @MainActor () -> AsyncStream<Strings?>,
        shouldFinishStateObservation: @escaping @MainActor (OperationState) -> Bool
    ) {
        self.operationState = initialState
        self.makeStateStream = makeStateStream
        self.makeStringsStream = makeStringsStream
        self.shouldFinishStateObservation = shouldFinishStateObservation
    }

    internal func observe() async {
        guard !Task.isCancelled, !shouldFinishStateObservation(operationState) else { return }
        observationGeneration += 1
        let generation = observationGeneration
        let stateStream = makeStateStream()
        let stringsStream = makeStringsStream()

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await self.observeStrings(stringsStream, generation: generation)
            }

            for await state in stateStream {
                guard !Task.isCancelled, generation == observationGeneration else { break }
                operationState = state
                if shouldFinishStateObservation(state) { break }
            }
            group.cancelAll()
        }
    }

    private func observeStrings(_ stream: AsyncStream<Strings?>, generation: Int) async {
        for await strings in stream {
            guard !Task.isCancelled, generation == observationGeneration else { break }
            if let strings { resolvedStrings = strings }
        }
    }
}
