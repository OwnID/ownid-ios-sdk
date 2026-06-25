import Foundation
import Testing

struct ModelJSON {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    func data<T: Encodable>(encoding value: T) throws -> Data {
        try encoder.encode(value)
    }

    func string<T: Encodable>(encoding value: T) throws -> String {
        let data = try data(encoding: value)
        return try #require(String(data: data, encoding: .utf8))
    }

    func object<T: Encodable>(encoding value: T) throws -> [String: Any] {
        let json = try JSONSerialization.jsonObject(with: data(encoding: value))
        return try #require(json as? [String: Any])
    }
}
