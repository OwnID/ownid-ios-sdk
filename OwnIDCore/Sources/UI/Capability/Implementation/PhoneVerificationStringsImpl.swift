import Foundation

/// Maps phone verification server keys into typed strings and fills missing keys from embedded defaults.
internal final class PhoneVerificationStringsEmbeddedRepositoryImpl: PhoneVerificationStringsEmbeddedRepository {

    internal func fallbackToEmbedded<P: StringsParams>(params: P, map: [String: String]) -> PhoneVerificationStrings {
        let defaultStrings = PhoneVerificationStrings.default

        return PhoneVerificationStrings(
            title: map["title"] ?? defaultStrings.title,
            message: map["message"] ?? defaultStrings.message,
            description: map["description"] ?? defaultStrings.description,
            resend: map["resend"] ?? defaultStrings.resend,
            cancel: map["cancel"] ?? defaultStrings.cancel,
            notYou: map["notYou"] ?? defaultStrings.notYou
        )
    }
}

/// Reads phone verification strings from the server locale data source.
///
/// Missing locale data emits `nil`; missing individual keys are omitted so the embedded repository can fill them.
/// Unavailable or unreadable persisted locale payloads are visible here as missing server data; suppressed refresh
/// failures may continue serving previously available data when a payload exists.
internal final class PhoneVerificationStringsServerRepositoryImpl: PhoneVerificationStringsServerRepository {
    private let serverLocaleProvider: any ServerLocaleDataSourceProvider
    private let prefix = ["steps", "otp"]

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
                    strings["title"] = dataSource.getString(key: self.prefix[0], self.prefix[1], "verify", "sms", "title")
                    strings["message"] = dataSource.getString(key: self.prefix[0], self.prefix[1], "sms", "verify", "message")
                    strings["description"] = dataSource.getString(key: self.prefix[0], self.prefix[1], "sms", "verify", "description")
                    strings["resend"] = dataSource.getString(key: self.prefix[0], self.prefix[1], "sms", "verify", "resend")
                    strings["cancel"] = dataSource.getString(key: self.prefix[0], self.prefix[1], "sms", "verify", "cancel")
                    strings["notYou"] = dataSource.getString(key: self.prefix[0], self.prefix[1], "sms", "verify", "not-you")

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
internal struct PhoneVerificationStringsServerRepositoryEmptyFallback: PhoneVerificationStringsServerRepository {
    internal func getStrings<P: StringsParams>(languageTag: LanguageTag, params: P) -> AsyncStream<[String: String]?> {
        AsyncStream { continuation in
            continuation.yield([:])
            continuation.finish()
        }
    }
}
