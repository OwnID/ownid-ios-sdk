import Foundation

final class CancellablePendingValue<Value: Sendable>: @unchecked Sendable {
    private let value: Value
    private let lock = NSLock()
    private var continuations: [CheckedContinuation<Value, Never>] = []
    private var isCanceled = false

    init(_ value: Value) {
        self.value = value
    }

    func wait() async -> Value {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let shouldResumeImmediately: Bool
                lock.lock()
                if isCanceled {
                    shouldResumeImmediately = true
                } else {
                    continuations.append(continuation)
                    shouldResumeImmediately = false
                }
                lock.unlock()

                if shouldResumeImmediately {
                    continuation.resume(returning: value)
                }
            }
        } onCancel: {
            finish()
        }
    }

    private func finish() {
        let continuations: [CheckedContinuation<Value, Never>]
        lock.lock()
        isCanceled = true
        continuations = self.continuations
        self.continuations.removeAll()
        lock.unlock()

        for continuation in continuations {
            continuation.resume(returning: value)
        }
    }
}
