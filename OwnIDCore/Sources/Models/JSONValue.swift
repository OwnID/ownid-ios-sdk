import Foundation

/// A type-safe representation of an arbitrary JSON value.
///
/// Supports strings, numbers, booleans, arrays, dictionaries, and null. `Codable` decodes JSON numbers as ``int(_:)``
/// when they fit in `Int`, otherwise as ``double(_:)`; encoding writes the active case back as the matching JSON value.
/// Literal conformances make it possible to build nested values with Swift literals.
public enum JSONValue: Sendable, Codable, Hashable {
    case string(String)

    case int(Int)

    case double(Double)

    case bool(Bool)

    case array([JSONValue])

    case dictionary([String: JSONValue])

    case null

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else if let doubleValue = try? container.decode(Double.self) {
            self = .double(doubleValue)
        } else if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
        } else if let arrayValue = try? container.decode([JSONValue].self) {
            self = .array(arrayValue)
        } else if let dictionaryValue = try? container.decode([String: JSONValue].self) {
            self = .dictionary(dictionaryValue)
        } else if container.decodeNil() {
            self = .null
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown JSON value")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .dictionary(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

extension JSONValue {
    internal init(_ value: String) {
        self = .string(value)
    }

    internal init(_ value: String?) {
        if let value = value {
            self = .string(value)
        } else {
            self = .null
        }
    }

    internal init(_ value: Int) {
        self = .int(value)
    }

    internal init(_ value: Double) {
        self = .double(value)
    }

    internal init(_ value: Bool) {
        self = .bool(value)
    }

    internal init(_ value: [JSONValue]) {
        self = .array(value)
    }

    internal init(_ value: [String: JSONValue]) {
        self = .dictionary(value)
    }

    internal init(_ value: [String: String?]) {
        var result: [String: JSONValue] = [:]
        for (key, optionalValue) in value {
            if let unwrapped = optionalValue {
                result[key] = .string(unwrapped)
            } else {
                result[key] = .null
            }
        }
        self = .dictionary(result)
    }

    /// Converts Foundation-style JSON values to ``JSONValue``.
    ///
    /// Unsupported values are represented as ``null``. Arrays and dictionaries are converted recursively.
    internal init(from any: Any) {
        if let str = any as? String {
            self = .string(str)
        } else if let int = any as? Int {
            self = .int(int)
        } else if let double = any as? Double {
            self = .double(double)
        } else if let bool = any as? Bool {
            self = .bool(bool)
        } else if let array = any as? [Any] {
            let jsonArray = array.compactMap { JSONValue(from: $0) }
            self = .array(jsonArray)
        } else if let dict = any as? [String: Any] {
            let jsonDict = dict.compactMapValues { JSONValue(from: $0) }
            self = .dictionary(jsonDict)
        } else if any is NSNull {
            self = .null
        } else {
            self = .null
        }
    }
}

extension JSONValue {
    public var stringValue: String? {
        switch self {
        case .string(let value):
            return value
        default:
            return nil
        }
    }

    public var intValue: Int? {
        switch self {
        case .int(let value):
            return value
        default:
            return nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .double(let value):
            return value
        default:
            return nil
        }
    }

    public var boolValue: Bool? {
        switch self {
        case .bool(let value):
            return value
        default:
            return nil
        }
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self {
            return value
        }
        return nil
    }

    public var dictionaryValue: [String: JSONValue]? {
        if case .dictionary(let value) = self {
            return value
        }
        return nil
    }
}

extension JSONValue {
    /// Returns the dictionary member for `key`, or `nil` when this value is not a dictionary or the key is missing.
    public subscript(key: String) -> JSONValue? {
        return dictionaryValue?[key]
    }

    /// Returns the array element at `index`, or `nil` when this value is not an array or the index is out of bounds.
    public subscript(index: Int) -> JSONValue? {
        guard case .array(let array) = self, index >= 0 && index < array.count else {
            return nil
        }
        return array[index]
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    public init(stringLiteral value: StringLiteralType) {
        self = .string(value)
    }
}

extension JSONValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: IntegerLiteralType) {
        self = .int(value)
    }
}

extension JSONValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: FloatLiteralType) {
        self = .double(value)
    }
}

extension JSONValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: BooleanLiteralType) {
        self = .bool(value)
    }
}

extension JSONValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JSONValue...) {
        self = .array(elements)
    }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
    /// Creates a JSON object from Swift dictionary-literal elements.
    ///
    /// If the literal repeats a key, the last value wins.
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        var dict: [String: JSONValue] = [:]
        for (key, value) in elements {
            dict[key] = value
        }
        self = .dictionary(dict)
    }
}

extension JSONValue: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) {
        self = .null
    }
}
