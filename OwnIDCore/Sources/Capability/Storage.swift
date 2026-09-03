import Foundation

/// Typed key-value storage capability for SDK-owned persisted data.
///
/// Values are stored by key as ``String``, ``Bool``, ``Int64``, or ``Double`` values. Get methods return the stored
/// value, or the supplied default when the key is absent. On load, the default implementation logs unreadable or
/// corrupted storage and starts with an empty store. The default implementation logs and rethrows mutation failures.
public protocol Storage: Capability, Sendable {
    /// Returns the stored String, or `defaultValue` if the key is absent from the current store.
    ///
    /// - Parameters:
    ///   - key: Storage key to look up.
    ///   - defaultValue: Value returned when the key is absent.
    /// - Returns: The stored value or `defaultValue`.
    func getString(forKey key: String, defaultValue: String?) async -> String?
    /// Persists a String value under `key`.
    ///
    /// - Throws: If the value cannot be persisted.
    func putString(_ value: String, forKey key: String) async throws

    /// Returns the stored Bool, or `defaultValue` if the key is absent from the current store.
    ///
    /// - Parameters:
    ///   - key: Storage key to look up.
    ///   - defaultValue: Value returned when the key is absent.
    /// - Returns: The stored value or `defaultValue`.
    func getBool(forKey key: String, defaultValue: Bool?) async -> Bool?
    /// Persists a Bool value under `key`.
    ///
    /// - Throws: If the value cannot be persisted.
    func putBool(_ value: Bool, forKey key: String) async throws

    /// Returns the stored number, or `defaultValue` if the key is absent from the current store.
    ///
    /// - Parameters:
    ///   - key: Storage key to look up.
    ///   - defaultValue: Value returned when the key is absent.
    /// - Returns: The stored value or `defaultValue`.
    func getNumber(forKey key: String, defaultValue: Int64?) async -> Int64?
    /// Persists a number value under `key`.
    ///
    /// - Throws: If the value cannot be persisted.
    func putNumber(_ value: Int64, forKey key: String) async throws

    /// Returns the stored Double, or `defaultValue` if the key is absent from the current store.
    ///
    /// - Parameters:
    ///   - key: Storage key to look up.
    ///   - defaultValue: Value returned when the key is absent.
    /// - Returns: The stored value or `defaultValue`.
    func getDouble(forKey key: String, defaultValue: Double?) async -> Double?
    /// Persists a Double value under `key`.
    ///
    /// - Throws: If the value cannot be persisted.
    func putDouble(_ value: Double, forKey key: String) async throws

    /// Removes the value stored under `key`.
    ///
    /// - Throws: If the updated store cannot be persisted.
    func remove(forKey key: String) async throws
}
