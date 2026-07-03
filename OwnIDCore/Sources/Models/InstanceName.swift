import Foundation

/// Identifies an OwnID SDK instance by name.
///
/// Use named instances when one app process must keep separate OwnID configurations or provider scopes. The
/// ``default`` instance is used when no explicit name is provided.
///
/// Names are compared by exact ``value`` and ``description`` returns the raw value. The SDK does not normalize, trim,
/// or reject blank values, so use a stable non-empty name for app-created instances.
public struct InstanceName: Hashable, CustomStringConvertible, Sendable {
    public let value: String

    public static let `default` = InstanceName(value: "DEFAULT")

    public init(value: String) {
        self.value = value
    }

    public var description: String {
        return value
    }
}
