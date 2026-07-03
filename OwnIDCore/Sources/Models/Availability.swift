import Foundation

/// Describes whether an SDK action can start with the current input and runtime state.
///
/// When the action cannot start, ``unavailable(_:)`` contains a human-readable explanation that can be logged
/// while integrating the SDK. Do not branch product logic on exact message text.
public enum Availability: Sendable {
    case available

    /// The action cannot start with the provided input.
    /// The associated value is human-readable diagnostic text. The SDK does not guarantee stable wording.
    case unavailable(String)
}

extension Availability {
    /// Invokes `action` if this availability is `.available`.
    ///
    /// Returns the original availability unchanged for fluent chaining.
    @discardableResult
    public func onAvailable(_ action: () -> Void) -> Self {
        if case .available = self { action() }
        return self
    }

    /// Invokes `action` if this availability is `.unavailable`.
    ///
    /// The action receives the unavailable message, which is diagnostic text for integration and logging, not a stable
    /// product decision value.
    ///
    /// Returns the original availability unchanged for fluent chaining.
    @discardableResult
    public func onUnavailable(_ action: (String) -> Void) -> Self {
        if case .unavailable(let message) = self { action(message) }
        return self
    }
}
