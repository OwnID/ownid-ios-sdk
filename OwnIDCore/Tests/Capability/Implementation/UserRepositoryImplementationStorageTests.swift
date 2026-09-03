import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

// Covers: STORAGE-010, STORAGE-030
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
        #expect(storedJSON["loginId"]?["id"]?.stringValue == "person@example.test")
        #expect(storedJSON["loginId"]?["type"]?.stringValue == "Email")
        #expect(storedJSON["loginID"] == nil)
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

    @Test func `Storage mutation failures are suppressed`() async throws {
        let storage = MemoryStorage(failsMutations: true)
        let repository = UserRepositoryImpl(storage: storage, coder: JSONCoderImpl())
        let user = User(
            loginID: LoginID(id: "person@example.test", type: .email),
            authMethod: .passkey
        )

        try await repository.setLastUser(user)
        await repository.clearLastUser()

        #expect(await storage.mutationAttempts == [.putString, .remove])
        #expect(await storage.string(forKey: "LAST_USER") == nil)
    }

    @Test func `Codec failures remain observable`() async throws {
        let user = User(
            loginID: LoginID(id: "person@example.test", type: .email),
            authMethod: .passkey
        )
        let encodingRepository = UserRepositoryImpl(storage: MemoryStorage(), coder: FailingUserRepositoryJSONCoder())

        await #expect(throws: UserRepositoryTestError.codecFailure) {
            try await encodingRepository.setLastUser(user)
        }

        let decodingStorage = MemoryStorage(strings: ["LAST_USER": "not decoded by the failing coder"])
        let decodingRepository = UserRepositoryImpl(storage: decodingStorage, coder: FailingUserRepositoryJSONCoder())

        await #expect(throws: UserRepositoryTestError.codecFailure) {
            _ = try await decodingRepository.lastUser()
        }
    }
}

private actor MemoryStorage: Storage {
    enum Mutation: Equatable, Sendable {
        case putString
        case remove
    }

    private var strings = [String: String]()
    private var bools = [String: Bool]()
    private var numbers = [String: Int64]()
    private var doubles = [String: Double]()
    private let failsMutations: Bool
    private var recordedMutationAttempts: [Mutation] = []

    init(strings: [String: String] = [:], failsMutations: Bool = false) {
        self.strings = strings
        self.failsMutations = failsMutations
    }

    var mutationAttempts: [Mutation] { recordedMutationAttempts }

    func string(forKey key: String) -> String? {
        strings[key]
    }

    func getString(forKey key: String, defaultValue: String?) async -> String? {
        strings[key] ?? defaultValue
    }

    func putString(_ value: String, forKey key: String) async throws {
        recordedMutationAttempts.append(.putString)
        if failsMutations { throw UserRepositoryTestError.storageFailure }
        strings[key] = value
    }

    func getBool(forKey key: String, defaultValue: Bool?) async -> Bool? {
        bools[key] ?? defaultValue
    }

    func putBool(_ value: Bool, forKey key: String) async throws {
        if failsMutations { throw UserRepositoryTestError.storageFailure }
        bools[key] = value
    }

    func getNumber(forKey key: String, defaultValue: Int64?) async -> Int64? {
        numbers[key] ?? defaultValue
    }

    func putNumber(_ value: Int64, forKey key: String) async throws {
        if failsMutations { throw UserRepositoryTestError.storageFailure }
        numbers[key] = value
    }

    func getDouble(forKey key: String, defaultValue: Double?) async -> Double? {
        doubles[key] ?? defaultValue
    }

    func putDouble(_ value: Double, forKey key: String) async throws {
        if failsMutations { throw UserRepositoryTestError.storageFailure }
        doubles[key] = value
    }

    func remove(forKey key: String) async throws {
        recordedMutationAttempts.append(.remove)
        if failsMutations { throw UserRepositoryTestError.storageFailure }
        strings.removeValue(forKey: key)
        bools.removeValue(forKey: key)
        numbers.removeValue(forKey: key)
        doubles.removeValue(forKey: key)
    }
}

private enum UserRepositoryTestError: Error, Equatable, Sendable {
    case storageFailure
    case codecFailure
}

private struct FailingUserRepositoryJSONCoder: JSONCoder {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    func encodeToString<T: Encodable>(_ value: T) throws -> String {
        throw UserRepositoryTestError.codecFailure
    }

    func decodeFromString<T: Decodable>(_ string: String, as type: T.Type) throws -> T {
        throw UserRepositoryTestError.codecFailure
    }

    func encodeToJSONValue<T: Encodable>(_ value: T) throws -> JSONValue {
        throw UserRepositoryTestError.codecFailure
    }

    func decodeFromJSONValue<T: Decodable>(_ element: JSONValue, as type: T.Type) throws -> T {
        throw UserRepositoryTestError.codecFailure
    }
}
