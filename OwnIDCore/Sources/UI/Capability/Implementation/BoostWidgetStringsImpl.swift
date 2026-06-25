import Foundation

/// Maps Boost widget server keys into typed strings and fills missing keys from embedded defaults.
internal final class BoostWidgetStringsEmbeddedRepositoryImpl: BoostWidgetStringsEmbeddedRepository {
    typealias S = BoostWidgetStrings

    internal func fallbackToEmbedded<P: StringsParams>(params: P, map: [String: String]) -> BoostWidgetStrings {
        let defaultStrings = BoostWidgetStrings.default
        return BoostWidgetStrings(
            skipPassword: map["skipPassword"] ?? defaultStrings.skipPassword,
            or: map["or"] ?? defaultStrings.or
        )
    }
}

/// Reads Boost widget strings from the server locale data source.
///
/// Missing locale data emits `nil`; missing individual keys are omitted so the embedded repository can fill them.
/// Unavailable or unreadable persisted locale payloads are visible here as missing server data; suppressed refresh
/// failures may continue serving previously available data when a payload exists.
internal final class BoostWidgetStringsServerRepositoryImpl: BoostWidgetStringsServerRepository {
    private let serverLocaleProvider: any ServerLocaleDataSourceProvider
    private let prefix = ["widgets"]

    internal init(serverLocaleProvider: any ServerLocaleDataSourceProvider) {
        self.serverLocaleProvider = serverLocaleProvider
    }

    internal func getStrings<P: StringsParams>(languageTag: LanguageTag, params: P) -> AsyncStream<[String: String]?> {
        let dataSourceStream = serverLocaleProvider.getDataSource(for: languageTag)
        return AsyncStream { continuation in
            let streamTask = Task {
                for await dataSource in dataSourceStream {
                    guard let dataSource = dataSource else {
                        continuation.yield(nil)
                        continue
                    }

                    var strings = [String: String]()
                    strings["skipPassword"] = dataSource.getString(key: self.prefix[0], "sbs-button", "skipPassword")
                    strings["or"] = dataSource.getString(key: self.prefix[0], "sbs-button", "or")

                    continuation.yield(strings.compactMapValues { $0 })
                }
            }
            continuation.onTermination = { @Sendable _ in streamTask.cancel() }
        }
    }
}

/// Server repository used when locale data source setup is unavailable.
///
/// Emits an empty map so string resolution completes with embedded defaults.
internal struct BoostWidgetStringsServerRepositoryEmptyFallback: BoostWidgetStringsServerRepository {
    internal func getStrings<P: StringsParams>(languageTag: LanguageTag, params: P) -> AsyncStream<[String: String]?> {
        AsyncStream { continuation in
            continuation.yield([:])
            continuation.finish()
        }
    }
}
