import Foundation

func withOwnIDRootStateTestLock<T>(_ operation: () async throws -> T) async throws -> T {
    let permit = await OwnIDRootStateTestLock.shared.acquire()

    do {
        let result = try await operation()
        await permit.release()
        return result
    } catch {
        await permit.release()
        throw error
    }
}

struct OwnIDRootStateTestPermit: Sendable {
    fileprivate let lock: OwnIDRootStateTestLock

    func release() async {
        await lock.release()
    }
}

actor OwnIDRootStateTestLock {
    static let shared = OwnIDRootStateTestLock()

    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async -> OwnIDRootStateTestPermit {
        if isLocked {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        } else {
            isLocked = true
        }

        return OwnIDRootStateTestPermit(lock: self)
    }

    fileprivate func release() {
        if waiters.isEmpty {
            isLocked = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
