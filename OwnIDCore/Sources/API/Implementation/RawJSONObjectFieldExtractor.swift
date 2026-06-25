import Foundation

internal enum RawJSONObjectFieldExtractor {
    private static func corrupted(_ message: String) -> DecodingError {
        .dataCorrupted(.init(codingPath: [], debugDescription: message))
    }

    internal static func extractRequiredTopLevelRawValue(from json: String, fieldName: String) throws -> String {
        guard let value = try extractTopLevelRawValue(from: json, fieldName: fieldName) else {
            throw corrupted("Missing required field \(fieldName).")
        }
        return value
    }

    private static func extractTopLevelRawValue(from json: String, fieldName: String) throws -> String? {
        let bytes = Array(json.utf8)
        let expectedFieldNameBytes = Array(fieldName.utf8)
        var index = skipWhitespace(bytes, from: 0)

        guard index < bytes.count, bytes[index] == 123 else { throw corrupted("Expected root JSON object.") }
        index += 1

        index = skipWhitespace(bytes, from: index)
        if index < bytes.count, bytes[index] == 125 {
            index += 1
            try ensureOnlyTrailingWhitespace(bytes, from: index)
            return nil
        }

        while true {
            index = skipWhitespace(bytes, from: index)
            let keyTokenStart = index
            let afterKey = try skipJSONStringToken(bytes, from: keyTokenStart)
            index = skipWhitespace(bytes, from: afterKey)

            guard index < bytes.count, bytes[index] == 58 else { throw corrupted("Expected ':' after key.") }
            index += 1
            index = skipWhitespace(bytes, from: index)

            let valueStart = index
            let valueEnd = try skipJSONValue(bytes, from: valueStart)

            if matchesUnescapedKeyToken(bytes, keyTokenStart: keyTokenStart, keyTokenEnd: afterKey, expected: expectedFieldNameBytes) {
                return try normalizeExtractedValue(bytes, valueStart: valueStart, valueEnd: valueEnd)
            }

            index = skipWhitespace(bytes, from: valueEnd)
            guard index < bytes.count else { throw corrupted("Unexpected end of JSON object.") }

            switch bytes[index] {
            case 44:
                index += 1
            case 125:
                index += 1
                try ensureOnlyTrailingWhitespace(bytes, from: index)
                return nil
            default:
                throw corrupted("Expected ',' or '}' after value.")
            }
        }
    }

    private static func normalizeExtractedValue(_ bytes: [UInt8], valueStart: Int, valueEnd: Int) throws -> String {
        guard valueStart < valueEnd else {
            throw corrupted("Unexpected empty JSON value.")
        }

        guard bytes[valueStart] == 34 else {
            return String(decoding: bytes[valueStart..<valueEnd], as: UTF8.self)
        }

        do {
            return try JSONDecoder().decode(String.self, from: Data(bytes[valueStart..<valueEnd]))
        } catch {
            throw corrupted("Invalid JSON string token.")
        }
    }

    private static func skipJSONValue(_ bytes: [UInt8], from start: Int) throws -> Int {
        guard start < bytes.count else { throw corrupted("Unexpected end of JSON while reading value.") }

        switch bytes[start] {
        case 34:
            return try skipJSONStringToken(bytes, from: start)
        case 123:
            return try skipNested(bytes, from: start, open: 123, close: 125)
        case 91:
            return try skipNested(bytes, from: start, open: 91, close: 93)
        case 116:
            return try consumeLiteral(bytes, from: start, literal: Array("true".utf8))
        case 102:
            return try consumeLiteral(bytes, from: start, literal: Array("false".utf8))
        case 110:
            return try consumeLiteral(bytes, from: start, literal: Array("null".utf8))
        case 45, 48...57:
            return try skipJSONNumber(bytes, from: start)
        default:
            throw corrupted("Unsupported JSON value at index \(start).")
        }
    }

    private static func skipJSONStringToken(_ bytes: [UInt8], from start: Int) throws -> Int {
        guard start < bytes.count, bytes[start] == 34 else {
            throw corrupted("Expected JSON string token at index \(start).")
        }

        var index = start + 1
        while index < bytes.count {
            let current = bytes[index]
            switch current {
            case 34:
                return index + 1
            case 92:
                index += 1
                guard index < bytes.count else {
                    throw corrupted("Invalid escape sequence in JSON string token.")
                }
                if bytes[index] == 117 {
                    guard index + 4 < bytes.count else {
                        throw corrupted("Invalid unicode escape sequence in JSON string token.")
                    }
                    index += 4
                }
            default:
                if current < 0x20 {
                    throw corrupted("Unescaped control character in JSON string token.")
                }
            }
            index += 1
        }

        throw corrupted("Unterminated JSON string token.")
    }

    private static func matchesUnescapedKeyToken(_ bytes: [UInt8], keyTokenStart: Int, keyTokenEnd: Int, expected: [UInt8]) -> Bool {
        var source = keyTokenStart + 1
        let sourceEnd = keyTokenEnd - 1
        var target = 0

        while source < sourceEnd {
            let current = bytes[source]
            if current == 92 { return false }
            if target >= expected.count || current != expected[target] { return false }
            source += 1
            target += 1
        }

        return target == expected.count
    }

    private static func skipNested(_ bytes: [UInt8], from start: Int, open: UInt8, close: UInt8) throws -> Int {
        var index = start + 1
        var depth = 1
        var inString = false
        var escaped = false

        while index < bytes.count {
            let current = bytes[index]

            if inString {
                if escaped {
                    escaped = false
                } else if current == 92 {
                    escaped = true
                } else if current == 34 {
                    inString = false
                }
                index += 1
                continue
            }

            switch current {
            case 34:
                inString = true
            case open:
                depth += 1
            case close:
                depth -= 1
                if depth == 0 {
                    return index + 1
                }
            default:
                break
            }

            index += 1
        }

        throw corrupted("Unterminated nested JSON value.")
    }

    private static func consumeLiteral(_ bytes: [UInt8], from start: Int, literal: [UInt8]) throws -> Int {
        let end = start + literal.count
        guard end <= bytes.count, bytes[start..<end].elementsEqual(literal) else {
            throw corrupted("Invalid JSON literal at index \(start).")
        }
        return end
    }

    private static func skipJSONNumber(_ bytes: [UInt8], from start: Int) throws -> Int {
        var index = start

        if bytes[index] == 45 { index += 1 }
        guard index < bytes.count else {
            throw corrupted("Invalid JSON number at index \(start).")
        }

        if bytes[index] == 48 {
            index += 1
        } else {
            guard (49...57).contains(bytes[index]) else {
                throw corrupted("Invalid JSON number at index \(start).")
            }
            index += 1
            while index < bytes.count, (48...57).contains(bytes[index]) { index += 1 }
        }

        if index < bytes.count, bytes[index] == 46 {
            index += 1
            guard index < bytes.count, (48...57).contains(bytes[index]) else {
                throw corrupted("Invalid JSON number at index \(start).")
            }
            while index < bytes.count, (48...57).contains(bytes[index]) { index += 1 }
        }

        if index < bytes.count, bytes[index] == 69 || bytes[index] == 101 {
            index += 1
            if index < bytes.count, bytes[index] == 43 || bytes[index] == 45 { index += 1 }
            guard index < bytes.count, (48...57).contains(bytes[index]) else {
                throw corrupted("Invalid JSON number at index \(start).")
            }
            while index < bytes.count, (48...57).contains(bytes[index]) { index += 1 }
        }

        return index
    }

    private static func ensureOnlyTrailingWhitespace(_ bytes: [UInt8], from start: Int) throws {
        if skipWhitespace(bytes, from: start) != bytes.count {
            throw corrupted("Unexpected trailing characters after root JSON object.")
        }
    }

    private static func skipWhitespace(_ bytes: [UInt8], from start: Int) -> Int {
        var index = start
        while index < bytes.count {
            switch bytes[index] {
            case 32, 10, 13, 9:
                index += 1
            default:
                return index
            }
        }
        return index
    }
}
