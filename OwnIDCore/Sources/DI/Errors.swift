import Foundation

/// Resolver failure thrown by ``DIContainerResolver/getOrThrow(type:)`` when a registered dependency cannot be created.
///
/// This is a public low-level SDK error that advanced consumers can catch for diagnostics. Normal integration code
/// should use typed API, operation, and flow failures instead of treating this error as control flow.
///
/// ``dependencyName`` identifies the requested type, ``scopeName`` identifies the scope where resolution started, and
/// ``entryPoint`` carries optional resolution context. The original factory, cycle, or runtime failure is exposed as
/// ``cause``.
public struct DependencyResolutionError: Error, CustomStringConvertible {
    public let dependencyName: String
    public let scopeName: String
    public let entryPoint: String?
    public let cause: any Error

    public var description: String {
        var s = "Failed to resolve \(dependencyName) in \(scopeName)"
        if let ep = entryPoint, !ep.isEmpty { s += " for \(ep)" }
        let msg = String(describing: cause)
        if !msg.isEmpty { s += ": \(msg)" }
        return s
    }
}

/// Resolver failure thrown by ``DIContainerResolver/getOrThrow(type:)`` when no dependency exists in the visible scope tree.
///
/// This is a public low-level SDK error that advanced consumers can catch for diagnostics. Normal integration code
/// should use typed API, operation, and flow failures instead of treating this error as control flow.
///
/// ``dependencyName`` identifies the missing type, ``scopeName`` identifies the scope where resolution started, and
/// ``entryPoint`` identifies the type originally requested. If resolving `A` reaches a missing `B`, ``dependencyName``
/// identifies `B` while ``entryPoint`` identifies `A`.
public struct MissingDependencyError: Error, Sendable {
    public let dependencyName: String
    public let scopeName: String
    public let entryPoint: String?
}

internal struct IdentityConflictError: LocalizedError {
    let conflictingInstanceName: InstanceName

    var errorDescription: String? {
        "Identity is already in use by '\(conflictingInstanceName)'"
    }
}
