import Foundation

/// Default ``Storage`` for a single suite-scoped SDK storage name.
///
/// The instance persists values in SDK-owned storage associated with the configured suite name. Maintain one live
/// instance per suite so writes observe a single owner.
///
/// Unreadable or corrupted files are logged, deleted, and replaced by an empty in-memory store. Write and remove
/// failures are logged and rethrown without changing the in-memory store.
///
/// !!! MUST BE SINGLETON PER FILE NAME !!!
internal actor StorageImpl: Storage {

    private struct StoredValue: Codable {
        var string: String?
        var bool: Bool?
        var number: Int64?
        var double: Double?
    }

    private let fileURL: URL
    private let keyPrefix: String
    private let logger: OwnIDLogRouter?
    private var store: [String: StoredValue]

    internal init(
        suiteName: String,
        keyPrefix: String = "com.ownid.sdk.storage.",
        baseDirectoryURL: URL? = nil,
        logger: OwnIDLogRouter?
    ) {
        self.keyPrefix = keyPrefix
        self.logger = logger

        let directoryURL = Self.storageDirectory(baseDirectoryURL: baseDirectoryURL, logger: logger)
        self.fileURL = directoryURL.appendingPathComponent("\(Self.safeFileName(for: suiteName)).plist")
        self.store = Self.loadStore(from: fileURL, logger: logger)
    }

    internal func getString(forKey key: String, defaultValue: String? = nil) async -> String? {
        store[namespaced(key)]?.string ?? defaultValue
    }

    internal func putString(_ value: String, forKey key: String) async throws {
        try updateStore { store in
            store[namespaced(key)] = StoredValue(string: value)
        }
    }

    internal func getBool(forKey key: String, defaultValue: Bool? = nil) async -> Bool? {
        store[namespaced(key)]?.bool ?? defaultValue
    }

    internal func putBool(_ value: Bool, forKey key: String) async throws {
        try updateStore { store in
            store[namespaced(key)] = StoredValue(bool: value)
        }
    }

    internal func getNumber(forKey key: String, defaultValue: Int64? = nil) async -> Int64? {
        store[namespaced(key)]?.number ?? defaultValue
    }

    internal func putNumber(_ value: Int64, forKey key: String) async throws {
        try updateStore { store in
            store[namespaced(key)] = StoredValue(number: value)
        }
    }

    internal func getDouble(forKey key: String, defaultValue: Double? = nil) async -> Double? {
        store[namespaced(key)]?.double ?? defaultValue
    }

    internal func putDouble(_ value: Double, forKey key: String) async throws {
        try updateStore { store in
            store[namespaced(key)] = StoredValue(double: value)
        }
    }

    internal func remove(forKey key: String) async throws {
        try updateStore { store in
            store.removeValue(forKey: namespaced(key))
        }
    }

    private func namespaced(_ key: String) -> String { "\(keyPrefix)\(key)" }

    private static func loadStore(from fileURL: URL, logger: OwnIDLogRouter?) -> [String: StoredValue] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }

        do {
            let data = try Data(contentsOf: fileURL)
            return try PropertyListDecoder().decode([String: StoredValue].self, from: data)
        } catch {
            logger?.logW(
                source: Self.self,
                prefix: #function,
                message: "Failed to read stored SDK storage. Deleting corrupted file.",
                cause: error
            )
            try? FileManager.default.removeItem(at: fileURL)
            return [:]
        }
    }

    private func updateStore(_ update: (inout [String: StoredValue]) -> Void) throws {
        var candidate = store
        update(&candidate)

        do {
            try persistStore(candidate)
        } catch {
            logger?.logW(source: Self.self, prefix: #function, message: "Failed to persist SDK storage", cause: error)
            throw error
        }

        store = candidate
    }

    private func persistStore(_ candidate: [String: StoredValue]) throws {
        if candidate.isEmpty {
            do {
                try FileManager.default.removeItem(at: fileURL)
            } catch let error as CocoaError where error.code == .fileNoSuchFile {
                return
            }
            return
        }

        let data = try PropertyListEncoder().encode(candidate)
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        Self.excludeFromBackup(directoryURL, logger: logger)
        try data.write(to: fileURL, options: .atomic)
        Self.excludeFromBackup(fileURL, logger: logger)
    }

    private static func storageDirectory(baseDirectoryURL: URL?, logger: OwnIDLogRouter?) -> URL {
        if let baseDirectoryURL { return baseDirectoryURL }

        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return appSupport.appendingPathComponent("com.ownid.sdk/storage", isDirectory: true)
        }

        logger?.logW(
            source: Self.self,
            prefix: #function,
            message: "Application Support directory not found; falling back to temporaryDirectory"
        )
        return FileManager.default.temporaryDirectory.appendingPathComponent("com.ownid.sdk/storage", isDirectory: true)
    }

    private static func safeFileName(for suiteName: String) -> String {
        String(suiteName.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" })
    }

    private static func excludeFromBackup(_ url: URL, logger: OwnIDLogRouter?) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        do {
            try mutableURL.setResourceValues(values)
        } catch {
            logger?.logW(source: Self.self, prefix: #function, message: "Failed to mark path as excluded from backup: \(url.path)")
        }
    }
}
