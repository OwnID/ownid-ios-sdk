import Foundation

/// Keeps the latest resolved error strings for mapping error codes to user-visible messages.
///
/// The resolver subscribes to ``ErrorStringsProvider`` when one is available and stores each non-`nil` emission.
/// Lookups use that latest stored value; when no value has been emitted, they use the fallback strings supplied for the
/// lookup.
internal final class ErrorStringsResolver: @unchecked Sendable {
    private let lock = NSLock()
    private var currentErrorStrings: ErrorStrings?

    init(errorStringsProvider: (any ErrorStringsProvider)?, taskScope: TaskScope) {
        guard let errorStringsProvider else { return }

        taskScope.spawn { [weak self] in
            for await maybeStrings in errorStringsProvider.getStrings(params: ErrorStringsParams()) {
                guard let self else { return }
                guard let strings = maybeStrings else { continue }

                lock.withLock {
                    currentErrorStrings = strings
                }
            }
        }
    }

    func toLocalizedMessage(errorCode: ErrorCode, fallbackErrorStrings: ErrorStrings) -> String {
        let errorStrings = lock.withLock { currentErrorStrings } ?? fallbackErrorStrings
        return errorCode.resolveLocalizedMessage(errorStrings: errorStrings)
    }
}
