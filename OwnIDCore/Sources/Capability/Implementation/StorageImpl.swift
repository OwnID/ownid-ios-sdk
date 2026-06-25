import Foundation

/// Default ``Storage`` for a single suite-scoped SDK storage name.
///
/// The instance persists values in SDK-owned storage associated with the configured suite name. Maintain one live
/// instance per suite so writes observe a single owner.
///
/// Unreadable or corrupted files are logged, deleted, and replaced by an empty in-memory store. Write and remove
/// failures are logged without throwing.
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

    internal func putString(_ value: String, forKey key: String) async {
        store[namespaced(key)] = StoredValue(string: value)
        saveStore()
    }

    internal func getBool(forKey key: String, defaultValue: Bool? = nil) async -> Bool? {
        store[namespaced(key)]?.bool ?? defaultValue
    }

    internal func putBool(_ value: Bool, forKey key: String) async {
        store[namespaced(key)] = StoredValue(bool: value)
        saveStore()
    }

    internal func getNumber(forKey key: String, defaultValue: Int64? = nil) async -> Int64? {
        store[namespaced(key)]?.number ?? defaultValue
    }

    internal func putNumber(_ value: Int64, forKey key: String) async {
        store[namespaced(key)] = StoredValue(number: value)
        saveStore()
    }

    internal func getDouble(forKey key: String, defaultValue: Double? = nil) async -> Double? {
        store[namespaced(key)]?.double ?? defaultValue
    }

    internal func putDouble(_ value: Double, forKey key: String) async {
        store[namespaced(key)] = StoredValue(double: value)
        saveStore()
    }

    internal func remove(forKey key: String) async {
        store.removeValue(forKey: namespaced(key))
        saveStore()
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

    private func saveStore() {
        do {
            if store.isEmpty {
                try? FileManager.default.removeItem(at: fileURL)
                return
            }

            let directoryURL = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
            Self.excludeFromBackup(directoryURL, logger: logger)
            let data = try PropertyListEncoder().encode(store)
            try data.write(to: fileURL, options: .atomic)
            Self.excludeFromBackup(fileURL, logger: logger)
        } catch {
            logger?.logW(source: Self.self, prefix: #function, message: "Failed to persist SDK storage", cause: error)
        }
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
