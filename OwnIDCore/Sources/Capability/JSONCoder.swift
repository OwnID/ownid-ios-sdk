import Foundation

/// JSON serialization and deserialization capability.
///
/// Encodes values to JSON strings or ``JSONValue`` and decodes them back using the configured encoder and decoder.
/// It does not redact or encrypt encoded values; callers that serialize tokens, login IDs, or user data own where those
/// strings are stored, logged, or sent.
public protocol JSONCoder: Capability, Sendable {
    /// The underlying ``JSONEncoder`` used for encoding operations.
    var encoder: JSONEncoder { get }
    /// The underlying ``JSONDecoder`` used for decoding operations.
    var decoder: JSONDecoder { get }

    /// Encodes `value` to a JSON string.
    ///
    /// - Parameters:
    ///   - value: Value to encode.
    /// - Returns: The encoded JSON string.
    /// - Throws: ``EncodingError`` when encoding fails or the result cannot be represented as UTF-8.
    func encodeToString<T: Encodable>(_ value: T) throws -> String

    /// Decodes a value of the given `type` from a JSON string.
    ///
    /// - Parameters:
    ///   - string: JSON string to decode.
    ///   - type: Type to decode.
    /// - Returns: The decoded value.
    /// - Throws: ``DecodingError`` when decoding fails or the string is not valid UTF-8 JSON.
    func decodeFromString<T: Decodable>(_ string: String, as type: T.Type) throws -> T

    /// Encodes `value` to a ``JSONValue``.
    ///
    /// - Parameters:
    ///   - value: Value to encode.
    /// - Returns: The encoded JSON value.
    /// - Throws: ``EncodingError`` when encoding fails.
    func encodeToJSONValue<T: Encodable>(_ value: T) throws -> JSONValue

    /// Decodes a value of the given `type` from a ``JSONValue``.
    ///
    /// - Parameters:
    ///   - element: JSON value to decode.
    ///   - type: Type to decode.
    /// - Returns: The decoded value.
    /// - Throws: ``DecodingError`` when decoding fails.
    func decodeFromJSONValue<T: Decodable>(_ element: JSONValue, as type: T.Type) throws -> T
}
