import Foundation

/// Base protocol for SDK capability boundaries.
///
/// Capabilities are available by default. Implementations that depend on runtime state, platform support,
/// configuration, or caller-supplied parameters override ``isAvailable(params:)``. Availability is owned by the
/// capability and is evaluated at the point where an SDK module asks to use it.
public protocol Capability {
    /// Returns `true` when this capability is ready to be used with the given `params`.
    ///
    /// Availability is a preflight signal only. A later operation, flow, provider call, or UI presentation can still
    /// fail or be canceled if runtime state changes after this check. The default implementation returns `true`.
    ///
    /// - Parameter params: Optional capability-specific parameters. Pass `nil` to check availability without explicit parameters.
    func isAvailable(params: (any CapabilityParams)?) async -> Bool
}

/// Marker protocol for parameter objects used by capability availability checks.
///
/// Capability-specific parameter types should conform to this protocol when they need to participate in
/// ``Capability/isAvailable(params:)`` checks.
public protocol CapabilityParams: Sendable {}

extension Capability {
    public func isAvailable(params: (any CapabilityParams)?) async -> Bool { true }
}
