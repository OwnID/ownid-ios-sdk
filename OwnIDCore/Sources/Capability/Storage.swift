import Foundation

/// Typed key-value storage capability for SDK-owned persisted data.
///
/// Values are stored by key as ``String``, ``Bool``, ``Int64``, or ``Double`` values. Get methods return the stored
/// value, or the supplied default when the key is absent. On load, the default implementation logs unreadable or
/// corrupted storage and starts with an empty store. Persistence failures are logged instead of throwing.
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
    /// The default implementation logs persistence failures instead of throwing.
    func putString(_ value: String, forKey key: String) async

    /// Returns the stored Bool, or `defaultValue` if the key is absent from the current store.
    ///
    /// - Parameters:
    ///   - key: Storage key to look up.
    ///   - defaultValue: Value returned when the key is absent.
    /// - Returns: The stored value or `defaultValue`.
    func getBool(forKey key: String, defaultValue: Bool?) async -> Bool?
    /// Persists a Bool value under `key`.
    ///
    /// The default implementation logs persistence failures instead of throwing.
    func putBool(_ value: Bool, forKey key: String) async

    /// Returns the stored number, or `defaultValue` if the key is absent from the current store.
    ///
    /// - Parameters:
    ///   - key: Storage key to look up.
    ///   - defaultValue: Value returned when the key is absent.
    /// - Returns: The stored value or `defaultValue`.
    func getNumber(forKey key: String, defaultValue: Int64?) async -> Int64?
    /// Persists a number value under `key`.
    ///
    /// The default implementation logs persistence failures instead of throwing.
    func putNumber(_ value: Int64, forKey key: String) async

    /// Returns the stored Double, or `defaultValue` if the key is absent from the current store.
    ///
    /// - Parameters:
    ///   - key: Storage key to look up.
    ///   - defaultValue: Value returned when the key is absent.
    /// - Returns: The stored value or `defaultValue`.
    func getDouble(forKey key: String, defaultValue: Double?) async -> Double?
    /// Persists a Double value under `key`.
    ///
    /// The default implementation logs persistence failures instead of throwing.
    func putDouble(_ value: Double, forKey key: String) async

    /// Removes the value stored under `key`.
    ///
    /// The default implementation logs persistence failures instead of throwing.
    func remove(forKey key: String) async
}
