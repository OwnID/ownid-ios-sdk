import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

struct UserRepositoryImplementationStorageTests {

    @Test func `Last user starts empty then round trips through storage JSON`() async throws {
        let storage = MemoryStorage()
        let repository = UserRepositoryImpl(storage: storage, coder: JSONCoderImpl())
        let user = User(
            loginID: LoginID(id: "person@example.test", type: .email),
            authMethod: .passkey
        )

        #expect(try await repository.lastUser() == nil)

        try await repository.setLastUser(user)

        let stored = try #require(await storage.string(forKey: "LAST_USER"))
        let storedJSON = try JSONCoderImpl().decodeFromString(stored, as: JSONValue.self)
        #expect(storedJSON["loginID"]?["id"]?.stringValue == "person@example.test")
        #expect(storedJSON["loginID"]?["type"]?.stringValue == "Email")
        #expect(storedJSON["authMethod"]?.stringValue == "passkey")

        let restored = try #require(try await repository.lastUser())
        #expect(restored.loginID == user.loginID)
        #expect(restored.authMethod == user.authMethod)
    }

    @Test func `Last user clear removes stored returning user`() async throws {
        let storage = MemoryStorage()
        let repository = UserRepositoryImpl(storage: storage, coder: JSONCoderImpl())

        try await repository.setLastUser(
            User(loginID: LoginID(id: "+15551234567", type: .phoneNumber), authMethod: .otp)
        )

        let stored = try #require(try await repository.lastUser())
        #expect(stored.authMethod == .otp)

        await repository.clearLastUser()

        #expect(try await repository.lastUser() == nil)
        #expect(await storage.string(forKey: "LAST_USER") == nil)
    }
}

private actor MemoryStorage: Storage {
    private var strings = [String: String]()
    private var bools = [String: Bool]()
    private var numbers = [String: Int64]()
    private var doubles = [String: Double]()

    func string(forKey key: String) -> String? {
        strings[key]
    }

    func getString(forKey key: String, defaultValue: String?) async -> String? {
        strings[key] ?? defaultValue
    }

    func putString(_ value: String, forKey key: String) async {
        strings[key] = value
    }

    func getBool(forKey key: String, defaultValue: Bool?) async -> Bool? {
        bools[key] ?? defaultValue
    }

    func putBool(_ value: Bool, forKey key: String) async {
        bools[key] = value
    }

    func getNumber(forKey key: String, defaultValue: Int64?) async -> Int64? {
        numbers[key] ?? defaultValue
    }

    func putNumber(_ value: Int64, forKey key: String) async {
        numbers[key] = value
    }

    func getDouble(forKey key: String, defaultValue: Double?) async -> Double? {
        doubles[key] ?? defaultValue
    }

    func putDouble(_ value: Double, forKey key: String) async {
        doubles[key] = value
    }

    func remove(forKey key: String) async {
        strings.removeValue(forKey: key)
        bools.removeValue(forKey: key)
        numbers.removeValue(forKey: key)
        doubles.removeValue(forKey: key)
    }
}
