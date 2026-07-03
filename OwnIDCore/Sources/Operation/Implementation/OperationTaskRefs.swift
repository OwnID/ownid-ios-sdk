import Foundation

/// Operation-owned holder for replaceable child tasks.
///
/// Operation runtimes use keyed refs for work owned by one operation lifecycle, such as timeout, UI, or error-string
/// updates. Replacing or clearing a key cancels only the task previously held for that key; settlement should clear the
/// operation-owned keys so late work cannot request a second terminal result. Cancellation is requested without
/// awaiting task completion, and the holder is synchronized so different operation callbacks can replace or clear refs.
internal final class OperationTaskRefs<Key: Hashable>: @unchecked Sendable {
    private let lock = NSLock()
    private var tasks: [Key: Task<Void, Never>] = [:]

    func replace(_ key: Key, with task: Task<Void, Never>?) {
        let previousTask: Task<Void, Never>? = lock.withLock {
            let current = tasks.removeValue(forKey: key)
            if let task {
                tasks[key] = task
            }
            return current
        }
        previousTask?.cancel()
    }

    func clear(_ key: Key) {
        replace(key, with: nil)
    }

    func clear<S: Sequence>(_ keys: S) where S.Element == Key {
        let previousTasks: [Task<Void, Never>] = lock.withLock {
            keys.compactMap { tasks.removeValue(forKey: $0) }
        }
        previousTasks.forEach { $0.cancel() }
    }
}
