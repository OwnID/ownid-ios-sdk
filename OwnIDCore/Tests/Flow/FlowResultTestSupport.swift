import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

enum FlowTestTimeout: Error, Sendable {
    case timedOut(String)
    case streamEnded(String)
}

func withFlowTimeout<T: Sendable>(
    _ description: String,
    seconds: UInt64 = 5,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            throw FlowTestTimeout.timedOut(description)
        }
        let value = try await group.next()!
        group.cancelAll()
        return value
    }
}

final class CapturedFlowValue<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value?
    private var waiters: [CheckedContinuation<Value, Never>] = []

    func set(_ value: Value) {
        let waiters = lock.withLock {
            self.value = value
            let waiters = self.waiters
            self.waiters.removeAll()
            return waiters
        }
        for waiter in waiters {
            waiter.resume(returning: value)
        }
    }

    func wait() async -> Value {
        let value = lock.withLock { self.value }
        if let value { return value }

        return await withCheckedContinuation { continuation in
            let value: Value? = lock.withLock {
                if let value = self.value {
                    return value
                }
                self.waiters.append(continuation)
                return nil
            }
            if let value {
                continuation.resume(returning: value)
            }
        }
    }
}

final class FlowLocked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func get() -> Value {
        lock.withLock { value }
    }

    func set(_ value: Value) {
        lock.withLock { self.value = value }
    }

    @discardableResult
    func mutate<T>(_ body: (inout Value) -> T) -> T {
        lock.withLock { body(&value) }
    }
}

func flowTaskScope() -> TaskScope {
    TaskScope(shutdownToken: ShutdownToken())
}

func requireSuccess<Success: Sendable, Failure: FlowFailure>(
    _ result: FlowResult<Success, Failure>,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws -> Success {
    switch result {
    case .success(let success):
        return success
    case .canceled(let reason):
        return try #require(
            nil as Success?,
            "Expected success, got cancellation: \(reason)",
            sourceLocation: sourceLocation
        )
    case .failure(let failure):
        return try #require(
            nil as Success?,
            "Expected success, got failure: \(failure)",
            sourceLocation: sourceLocation
        )
    }
}

func requireCancellation<Success: Sendable, Failure: FlowFailure>(
    _ result: FlowResult<Success, Failure>,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws -> Reason {
    switch result {
    case .canceled(let reason):
        return reason
    case .success(let success):
        return try #require(nil as Reason?, "Expected cancellation, got success: \(success)", sourceLocation: sourceLocation)
    case .failure(let failure):
        return try #require(nil as Reason?, "Expected cancellation, got failure: \(failure)", sourceLocation: sourceLocation)
    }
}

func requireFlowAvailable(
    _ availability: Availability,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws {
    switch availability {
    case .available:
        return
    case .unavailable(let message):
        _ = try #require(nil as Void?, "Expected available, got unavailable: \(message)", sourceLocation: sourceLocation)
    }
}

func requireFlowUnavailable(
    _ availability: Availability,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws -> String {
    switch availability {
    case .unavailable(let message):
        return message
    case .available:
        return try #require(nil as String?, "Expected unavailable, got available", sourceLocation: sourceLocation)
    }
}

func requireFailure<Success: Sendable, Failure: FlowFailure>(
    _ result: FlowResult<Success, Failure>,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws -> Failure {
    switch result {
    case .failure(let failure):
        return failure
    case .success(let success):
        return try #require(
            nil as Failure?,
            "Expected failure, got success: \(success)",
            sourceLocation: sourceLocation
        )
    case .canceled(let reason):
        return try #require(
            nil as Failure?,
            "Expected failure, got cancellation: \(reason)",
            sourceLocation: sourceLocation
        )
    }
}
