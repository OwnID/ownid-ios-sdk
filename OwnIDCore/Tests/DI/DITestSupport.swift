import Foundation

final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0

    var value: Int {
        lock.withLock { storedValue }
    }

    func increment() -> Int {
        lock.withLock {
            storedValue += 1
            return storedValue
        }
    }
}
