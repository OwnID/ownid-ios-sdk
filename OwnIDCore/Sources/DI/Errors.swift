import Foundation

/// Resolver failure thrown by ``DIContainerResolver/getOrThrow(type:)`` when a registered dependency cannot be created.
///
/// This is an internal SDK module-boundary error. Public API, operation, and flow entry points generally convert
/// dependency setup failures into their typed result failure instead of throwing this error directly.
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
/// This is an internal SDK module-boundary error. Public API, operation, and flow entry points generally convert missing
/// dependencies into their typed result failure instead of throwing this error directly.
///
/// ``dependencyName`` identifies the missing type, ``scopeName`` identifies the scope where resolution started, and
/// ``entryPoint`` carries optional resolution context.
public struct MissingDependencyError: Error, Sendable {
    public let dependencyName: String
    public let scopeName: String
    public let entryPoint: String?
}
