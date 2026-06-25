import Foundation

/// Persistence owner for server-provided locale payloads.
///
/// Content is scoped to the SDK app/environment identity. Callers read and write ``ServerLocaleContent`` values by
/// ``LanguageTag``; storage details are intentionally not part of the locale repository contract.
///
/// Corrupted or unreadable data is treated as unavailable content so string resolution can fall back to embedded copy.
/// Write failures are allowed to surface to the refresh path; readers should continue to tolerate missing content.
internal actor ServerLocaleDataStore {
    private let fileManager: FileManager
    private let cacheDirectory: URL
    private let isWritable: Bool
    private let suffix: String
    private let jsonCoder: any JSONCoder
    private let logger: OwnIDLogRouter?

    init(
        suffix: String,
        jsonCoder: any JSONCoder,
        fileManager: FileManager = .default,
        logger: OwnIDLogRouter?,
        forceTemporaryFallback: Bool = false
    ) {
        self.suffix = suffix
        self.jsonCoder = jsonCoder
        self.fileManager = fileManager
        self.logger = logger

        var cacheDirectoryURL: URL
        var writable = true
        if forceTemporaryFallback {
            cacheDirectoryURL = fileManager.temporaryDirectory.appendingPathComponent("com.ownid.sdk/locales/", isDirectory: true)
            logger?.logW(source: Self.self, prefix: #function, message: "Forced fallback to temporaryDirectory for locales cache")
        } else {
            let preferredBaseURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            if let base = preferredBaseURL {
                cacheDirectoryURL = base.appendingPathComponent("com.ownid.sdk/locales/", isDirectory: true)
            } else {
                cacheDirectoryURL = fileManager.temporaryDirectory.appendingPathComponent("com.ownid.sdk/locales/", isDirectory: true)
                logger?.logW(
                    source: Self.self,
                    prefix: #function,
                    message: "Caches directory not found; falling back to temporaryDirectory"
                )
            }
        }

        do {
            try self.fileManager.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            logger?.logW(
                source: Self.self,
                prefix: #function,
                message: "Failed to create locale cache directory at \(cacheDirectoryURL.path)",
                cause: error
            )
            let tmpFallback = fileManager.temporaryDirectory.appendingPathComponent("com.ownid.sdk/locales/", isDirectory: true)
            do {
                try self.fileManager.createDirectory(at: tmpFallback, withIntermediateDirectories: true, attributes: nil)
                cacheDirectoryURL = tmpFallback
            } catch {
                writable = false
                logger?.logW(
                    source: Self.self,
                    prefix: #function,
                    message: "Locales cache disabled: both preferred and fallback directories are unavailable; disk writes will be skipped"
                )
            }
        }

        self.cacheDirectory = cacheDirectoryURL
        self.isWritable = writable
    }

    func getContent(for languageTag: LanguageTag) -> ServerLocaleContent? {
        let url = fileURL(for: languageTag)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let contentString = String(data: data, encoding: .utf8) ?? ""
            return try jsonCoder.decodeFromString(contentString, as: ServerLocaleContent.self)
        } catch let decodeError {
            logger?.logW(
                source: Self.self,
                prefix: #function,
                message: "Failed to read content for \(languageTag): \(decodeError.localizedDescription). Removing corrupted cache at \(url.lastPathComponent)"
            )
            try? fileManager.removeItem(at: url)
            return nil
        }
    }

    func setContent(_ content: ServerLocaleContent, for languageTag: LanguageTag) async throws {
        guard isWritable else {
            logger?.logI(
                source: Self.self,
                prefix: #function,
                message: "Locales cache is not writable; skipping write for \(languageTag.tagString)_\(suffix).json"
            )
            return
        }
        let url = fileURL(for: languageTag)
        let contentString = try jsonCoder.encodeToString(content)
        guard let data = contentString.data(using: .utf8) else {
            throw EncodingError.invalidValue(
                content,
                EncodingError.Context(codingPath: [], debugDescription: "Failed to convert encoded JSON string to UTF-8 data.")
            )
        }

        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        try data.write(to: url, options: .atomic)
    }

    private func fileURL(for languageTag: LanguageTag) -> URL {
        cacheDirectory.appendingPathComponent("\(languageTag.tagString)_\(suffix).json")
    }
}
