import Foundation

/// Storage-backed ``UserRepository`` for the SDK's last-user record.
///
/// The repository serializes the complete ``User`` value into SDK-owned storage and returns `nil` when no record is
/// present. It does not add encryption, retention policy, or cross-app synchronization beyond the configured
/// ``Storage`` capability.
internal actor UserRepositoryImpl: UserRepository {
    private let storage: any Storage
    private let coder: any JSONCoder

    private static let keyLastUser = "LAST_USER"

    init(storage: any Storage, coder: any JSONCoder) {
        self.storage = storage
        self.coder = coder
    }

    func lastUser() async throws -> User? {
        guard let json = await storage.getString(forKey: Self.keyLastUser, defaultValue: nil) else { return nil }
        return try coder.decodeFromString(json, as: User.self)
    }

    func setLastUser(_ user: User) async throws {
        let string = try coder.encodeToString(user)
        await storage.putString(string, forKey: Self.keyLastUser)
    }

    func clearLastUser() async {
        await storage.remove(forKey: Self.keyLastUser)
    }
}
