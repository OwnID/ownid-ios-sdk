import Combine
import Foundation

@MainActor
internal final class VerificationOperationContentModel<OperationState, Strings>: ObservableObject {
    @Published internal var operationState: OperationState
    @Published internal var resolvedStrings: Strings?

    private let stateStream: AsyncStream<OperationState>
    private let stringsStream: AsyncStream<Strings?>
    private let shouldFinishStateObservation: @MainActor (OperationState) -> Bool
    private var stateTask: Task<Void, Never>?
    private var stringsTask: Task<Void, Never>?

    internal init(
        initialState: OperationState,
        stateStream: AsyncStream<OperationState>,
        stringsStream: AsyncStream<Strings?>,
        shouldFinishStateObservation: @escaping @MainActor (OperationState) -> Bool
    ) {
        self.operationState = initialState
        self.stateStream = stateStream
        self.stringsStream = stringsStream
        self.shouldFinishStateObservation = shouldFinishStateObservation
    }

    deinit {
        stateTask?.cancel()
        stringsTask?.cancel()
    }

    internal func startObserving() {
        guard stateTask == nil, stringsTask == nil else { return }

        stateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await state in stateStream {
                if Task.isCancelled { break }
                operationState = state
                if shouldFinishStateObservation(state) { break }
            }
        }

        stringsTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await strings in stringsStream.compactMap({ $0 }) {
                if Task.isCancelled { break }
                resolvedStrings = strings
            }
        }
    }
}
