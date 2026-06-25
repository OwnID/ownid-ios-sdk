import Foundation

/// Instance-owned task registry tied to ``ShutdownToken``.
///
/// Services use this scope for background work that should stop when the OwnID instance is destroyed or replaced.
/// Calling ``shutdown()`` or canceling the linked shutdown token runs registered shutdown handlers and cancels all
/// tracked tasks. New tasks are rejected after shutdown.
@_spi(OwnIDInternal) public final class TaskScope: @unchecked Sendable {
    private let lock = NSLock()
    private var closed = false
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var finishedBeforeRegistration: Set<UUID> = []
    private var shutdownHandlers: [UUID: @Sendable () -> Void] = [:]
    private let shutdownToken: ShutdownToken
    private var shutdownTokenHandlerId: UUID?

    /// Creates a task scope linked to the provided instance shutdown token.
    public init(shutdownToken: ShutdownToken) {
        self.shutdownToken = shutdownToken
        shutdownTokenHandlerId = shutdownToken.onCancel { [weak self] in
            self?.shutdown()
        }
    }

    /// Spawns a detached task tracked by this scope.
    ///
    /// The task does not inherit caller actor isolation and is canceled when the scope shuts down. If the scope is
    /// already shut down, this method returns `nil` and does not run `body`.
    @discardableResult
    public func spawn(
        priority: TaskPriority = .utility,
        onCancel: (@Sendable () -> Void)? = nil,
        _ body: @Sendable @escaping () async -> Void
    ) -> Task<Void, Never>? {
        lock.lock()
        if closed {
            lock.unlock()
            return nil
        }
        lock.unlock()

        let id = UUID()
        let task = Task.detached(priority: priority) { [weak self] in
            await withTaskCancellationHandler {
                await body()
            } onCancel: {
                onCancel?()
            }
            self?.finish(id: id)
        }

        lock.lock()
        if closed {
            lock.unlock()
            task.cancel()
            return nil
        }
        if finishedBeforeRegistration.remove(id) == nil {
            tasks[id] = task
        }
        lock.unlock()

        return task
    }

    /// Spawns a main-actor task tracked by this scope.
    ///
    /// The task is canceled when the scope shuts down. If the scope is already shut down, this method returns `nil`
    /// and does not run `body`.
    @discardableResult
    public func spawnOnMain(
        onCancel: (@Sendable () -> Void)? = nil,
        _ body: @MainActor @Sendable @escaping () async -> Void
    ) -> Task<Void, Never>? {
        lock.lock()
        if closed {
            lock.unlock()
            return nil
        }
        lock.unlock()

        let id = UUID()
        let task = Task { @MainActor [weak self] in
            await withTaskCancellationHandler {
                await body()
            } onCancel: {
                onCancel?()
            }
            self?.finish(id: id)
        }

        lock.lock()
        if closed {
            lock.unlock()
            task.cancel()
            return nil
        }
        if finishedBeforeRegistration.remove(id) == nil {
            tasks[id] = task
        }
        lock.unlock()

        return task
    }

    /// Runs shutdown handlers and cancels all tasks tracked by this scope.
    ///
    /// Shutdown is idempotent. After shutdown, future task-spawn requests return `nil` and future shutdown handlers run
    /// immediately.
    public func shutdown() {
        let shutdownItems: ([Task<Void, Never>], [@Sendable () -> Void]) = lock.withLock {
            if closed { return ([], []) }
            closed = true
            let all = Array(tasks.values)
            tasks.removeAll()
            finishedBeforeRegistration.removeAll()
            let handlers = Array(shutdownHandlers.values)
            shutdownHandlers.removeAll()
            return (all, handlers)
        }

        if let id = shutdownTokenHandlerId {
            shutdownToken.removeHandler(id)
            shutdownTokenHandlerId = nil
        }

        let (toCancel, handlers) = shutdownItems
        handlers.forEach { $0() }
        toCancel.forEach { $0.cancel() }
    }

    /// Registers a closure to run during scope shutdown.
    ///
    /// If the scope has already shut down, the closure runs synchronously and no handler ID is returned.
    ///
    /// - Returns: A handler ID that can be passed to ``removeShutdownHandler(_:)``, or `nil` when the handler already ran.
    @discardableResult
    public func onShutdown(_ handler: @escaping @Sendable () -> Void) -> UUID? {
        var shouldRunNow = false
        let id: UUID? = lock.withLock {
            if closed {
                shouldRunNow = true
                return nil
            }
            let id = UUID()
            shutdownHandlers[id] = handler
            return id
        }
        if shouldRunNow {
            handler()
        }
        return id
    }

    /// Removes a previously registered shutdown handler.
    public func removeShutdownHandler(_ id: UUID) {
        _ = lock.withLock {
            shutdownHandlers.removeValue(forKey: id)
        }
    }

    private func finish(id: UUID) {
        lock.withLock {
            guard !closed else { return }
            if tasks.removeValue(forKey: id) == nil {
                finishedBeforeRegistration.insert(id)
            }
        }
    }
}
