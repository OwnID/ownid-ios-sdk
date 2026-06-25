import Foundation

internal final class JSONCoderImpl: JSONCoder, @unchecked Sendable {
    internal let encoder: JSONEncoder
    internal let decoder: JSONDecoder

    private let lock = NSLock()

    internal init(encoder: JSONEncoder = JSONEncoder(), decoder: JSONDecoder = JSONDecoder()) {
        self.encoder = encoder
        self.decoder = decoder
    }

    internal func encodeToString<T: Encodable>(_ value: T) throws -> String {
        let data: Data = try lock.withLock { try encoder.encode(value) }
        guard let string = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(codingPath: [], debugDescription: "Failed to convert encoded JSON data to UTF-8 string.")
            )
        }
        return string
    }

    internal func decodeFromString<T: Decodable>(_ string: String, as type: T.Type) throws -> T {
        guard let data = string.data(using: .utf8) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], debugDescription: "Failed to convert string to UTF-8 data.")
            )
        }
        return try lock.withLock { try decoder.decode(T.self, from: data) }
    }

    internal func encodeToJSONValue<T: Encodable>(_ value: T) throws -> JSONValue {
        let data: Data = try lock.withLock { try encoder.encode(value) }
        return try lock.withLock { try decoder.decode(JSONValue.self, from: data) }
    }

    internal func decodeFromJSONValue<T: Decodable>(_ element: JSONValue, as type: T.Type) throws -> T {
        let data: Data = try lock.withLock { try encoder.encode(element) }
        return try lock.withLock { try decoder.decode(T.self, from: data) }
    }
}
