import Foundation

/// Instance-scoped cancellation signal shared by long-lived SDK services.
///
/// The root container cancels this token when an OwnID instance is destroyed or replaced. Services can either observe
/// ``stream()`` or register a handler with ``onCancel(_:)`` to release resources tied to that instance.
@_spi(OwnIDInternal) public final class ShutdownToken: @unchecked Sendable {
    private let lock = NSLock()
    private var canceled = false
    private var continuations: [UUID: AsyncStream<Void>.Continuation] = [:]
    private var handlers: [UUID: @Sendable () -> Void] = [:]

    public init() {}

    /// Returns a stream that finishes when the token is canceled.
    ///
    /// The stream does not emit values. If the token has already been canceled, the returned stream finishes
    /// immediately.
    public func stream() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let id = UUID()
            continuation.onTermination = { [weak self] _ in
                _ = self?.lock.withLock { self?.continuations.removeValue(forKey: id) }
            }

            let shouldFinish = lock.withLock {
                if canceled {
                    return true
                }
                continuations[id] = continuation
                return false
            }
            if shouldFinish {
                continuation.finish()
            }
        }
    }

    /// Cancels the token and notifies all current observers exactly once.
    public func cancel() {
        let (toFinish, toRun): ([AsyncStream<Void>.Continuation], [@Sendable () -> Void]) = lock.withLock {
            if canceled { return ([], []) }
            canceled = true
            let all = Array(continuations.values)
            continuations.removeAll()
            let handlersToRun = Array(handlers.values)
            handlers.removeAll()
            return (all, handlersToRun)
        }

        for continuation in toFinish {
            continuation.finish()
        }
        for handler in toRun {
            handler()
        }
    }

    /// Registers a closure to run when the token is canceled.
    ///
    /// If the token has already been canceled, the closure runs synchronously and no handler ID is returned.
    ///
    /// - Returns: A handler ID that can be passed to ``removeHandler(_:)``, or `nil` when the handler already ran.
    public func onCancel(_ handler: @escaping @Sendable () -> Void) -> UUID? {
        var shouldRunNow = false
        let id: UUID? = lock.withLock {
            if canceled {
                shouldRunNow = true
                return nil
            }
            let id = UUID()
            handlers[id] = handler
            return id
        }
        if shouldRunNow {
            handler()
        }
        return id
    }

    /// Removes a previously registered cancellation handler.
    public func removeHandler(_ id: UUID) {
        _ = lock.withLock {
            handlers.removeValue(forKey: id)
        }
    }
}
