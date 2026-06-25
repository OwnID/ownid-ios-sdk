import Foundation

enum TestTimeoutError: Error, Sendable {
    case timedOut(String)
}

func withTestTimeout<T: Sendable>(
    _ description: String,
    seconds: UInt64 = 5,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        defer { group.cancelAll() }
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            throw TestTimeoutError.timedOut(description)
        }
        let value = try await group.next()!
        return value
    }
}

func waitForTaskCancellation() async {
    await CancellablePendingValue(()).wait()
}

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

final class AsyncSignalRecorder<Entry: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Entry] = []
    private var waiters: [UUID: AsyncSignalWaiter<Entry>] = [:]

    var entries: [Entry] {
        lock.withLock { storage }
    }

    func append(_ entry: Entry) {
        let completed: [(CheckedContinuation<[Entry], any Error>, [Entry])] = lock.withLock {
            storage.append(entry)
            return popCompletedWaiters()
        }

        for (continuation, entries) in completed {
            continuation.resume(returning: entries)
        }
    }

    func waitForFirst(
        _ description: String,
        seconds: UInt64 = 5,
        where predicate: @escaping @Sendable (Entry) -> Bool
    ) async throws -> Entry {
        let entries = try await waitForMatches(description, seconds: seconds) { entries in
            entries.first(where: predicate).map { [$0] }
        }
        return entries[0]
    }

    func waitForCount(
        _ count: Int,
        _ description: String,
        seconds: UInt64 = 5,
        where predicate: @escaping @Sendable (Entry) -> Bool
    ) async throws -> [Entry] {
        try await waitForMatches(description, seconds: seconds) { entries in
            let matchingEntries = entries.filter(predicate)
            guard matchingEntries.count >= count else { return nil }
            return matchingEntries
        }
    }

    private func waitForMatches(
        _ description: String,
        seconds: UInt64,
        matching matcher: @escaping @Sendable ([Entry]) -> [Entry]?
    ) async throws -> [Entry] {
        try await withTestTimeout(description, seconds: seconds) {
            try await self.waitForMatches(matching: matcher)
        }
    }

    private func waitForMatches(
        matching matcher: @escaping @Sendable ([Entry]) -> [Entry]?
    ) async throws -> [Entry] {
        let token = AsyncSignalWaitToken()
        try Task.checkCancellation()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let registration = token.registerIfNotCancelled {
                    lock.lock()
                    defer { lock.unlock() }
                    if let entries = matcher(storage) {
                        return AsyncSignalRegistration.immediate(entries)
                    }
                    waiters[token.id] = AsyncSignalWaiter(matcher: matcher, continuation: continuation)
                    return .registered
                }

                switch registration {
                case .immediate(let entries):
                    continuation.resume(returning: entries)
                case .registered:
                    break
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            cancelWaiter(token)
        }
    }

    private func cancelWaiter(_ token: AsyncSignalWaitToken) {
        guard token.cancel() else { return }
        let continuation = lock.withLock {
            waiters.removeValue(forKey: token.id)?.continuation
        }
        continuation?.resume(throwing: CancellationError())
    }

    private func popCompletedWaiters() -> [(CheckedContinuation<[Entry], any Error>, [Entry])] {
        var completed: [(CheckedContinuation<[Entry], any Error>, [Entry])] = []
        for (id, waiter) in Array(waiters) {
            guard let entries = waiter.matcher(storage) else { continue }
            completed.append((waiter.continuation, entries))
            waiters.removeValue(forKey: id)
        }
        return completed
    }
}

private struct AsyncSignalWaiter<Entry: Sendable> {
    let matcher: @Sendable ([Entry]) -> [Entry]?
    let continuation: CheckedContinuation<[Entry], any Error>
}

private enum AsyncSignalRegistration<Entry: Sendable> {
    case immediate([Entry])
    case registered
    case cancelled
}

private final class AsyncSignalWaitToken: @unchecked Sendable {
    let id = UUID()

    private let lock = NSLock()
    private var isCancelled = false
    private var isRegistered = false

    func registerIfNotCancelled<Entry: Sendable>(
        _ registration: () -> AsyncSignalRegistration<Entry>
    ) -> AsyncSignalRegistration<Entry> {
        lock.lock()
        defer { lock.unlock() }
        if isCancelled {
            return .cancelled
        }

        let result = registration()
        if case .registered = result {
            isRegistered = true
        }
        return result
    }

    func cancel() -> Bool {
        lock.withLock {
            isCancelled = true
            return isRegistered
        }
    }
}
