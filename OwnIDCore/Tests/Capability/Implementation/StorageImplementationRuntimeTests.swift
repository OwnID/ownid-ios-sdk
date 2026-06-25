import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

struct StorageImplementationRuntimeTests {

    @Test func `Stored values persist after recreating storage actor`() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let suiteName = "persist-\(UUID().uuidString)"
        var storage: StorageImpl? = StorageImpl(suiteName: suiteName, baseDirectoryURL: directoryURL, logger: nil)

        await storage?.putString("person@example.test", forKey: "LAST_USER")
        await storage?.putBool(true, forKey: "FLAG")
        await storage?.putNumber(42, forKey: "COUNT")
        await storage?.putDouble(3.25, forKey: "RATIO")

        storage = nil

        let recreatedStorage = StorageImpl(suiteName: suiteName, baseDirectoryURL: directoryURL, logger: nil)

        #expect(await recreatedStorage.getString(forKey: "LAST_USER", defaultValue: nil) == "person@example.test")
        #expect(await recreatedStorage.getBool(forKey: "FLAG", defaultValue: false) == true)
        #expect(await recreatedStorage.getNumber(forKey: "COUNT", defaultValue: 0) == 42)
        #expect(await recreatedStorage.getDouble(forKey: "RATIO", defaultValue: 0) == 3.25)
    }

    @Test func `Corrupted storage file is logged deleted and replaced by empty state`() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let suiteName = "corrupt-\(UUID().uuidString)"
        let fileURL = storageFileURL(in: directoryURL, suiteName: suiteName)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data("not a plist".utf8).write(to: fileURL)

        let logs = LogCapture()
        let router = testLogRouter(sink: logs)
        var storage: StorageImpl? = StorageImpl(suiteName: suiteName, baseDirectoryURL: directoryURL, logger: router)

        #expect(await storage?.getString(forKey: "LAST_USER", defaultValue: "empty") == "empty")
        #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)

        let entry = try #require(logs.entries.first)
        #expect(logs.entries.count == 1)
        #expect(entry.level == .warn)
        #expect(entry.message.contains("corrupted file"))
        #expect(entry.hasCause)

        await storage?.putString("replacement", forKey: "LAST_USER")
        storage = nil

        let recreatedStorage = StorageImpl(suiteName: suiteName, baseDirectoryURL: directoryURL, logger: router)
        #expect(await recreatedStorage.getString(forKey: "LAST_USER", defaultValue: nil) == "replacement")
        #expect(logs.entries.count == 1)
    }

    @Test func `Suite names map to safe storage file names`() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let suiteName = "app/id:with spaces.and/slashes?"
        var storage: StorageImpl? = StorageImpl(suiteName: suiteName, baseDirectoryURL: directoryURL, logger: nil)

        await storage?.putString("value", forKey: "KEY")
        storage = nil

        let contents = try FileManager.default.contentsOfDirectory(atPath: directoryURL.path)

        #expect(contents == ["app_id_with_spaces_and_slashes_.plist"])
        #expect(FileManager.default.fileExists(atPath: directoryURL.appendingPathComponent("app").path) == false)
    }

    @Test func `Writable storage paths are excluded from backup`() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let suiteName = "backup-\(UUID().uuidString)"
        let fileURL = storageFileURL(in: directoryURL, suiteName: suiteName)
        let storage = StorageImpl(suiteName: suiteName, baseDirectoryURL: directoryURL, logger: nil)

        await storage.putString("value", forKey: "LAST_USER")

        let directoryValues = try directoryURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        let fileValues = try fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])

        #expect(directoryValues.isExcludedFromBackup == true)
        #expect(fileValues.isExcludedFromBackup == true)
    }
}

private func makeTemporaryDirectory() throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("StorageImplementationRuntimeTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    return directoryURL
}

private func storageFileURL(in directoryURL: URL, suiteName: String) -> URL {
    directoryURL.appendingPathComponent(safeFileName(for: suiteName)).appendingPathExtension("plist")
}

private func safeFileName(for suiteName: String) -> String {
    String(suiteName.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" })
}
