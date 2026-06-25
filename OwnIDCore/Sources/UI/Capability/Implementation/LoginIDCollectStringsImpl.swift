import Foundation

/// Maps login ID collection server keys into typed strings and fills missing keys from embedded defaults.
///
/// Embedded defaults depend on the collectable login ID types and whether the system can use passkeys. If no local
/// device information is available, passkey-capable wording is used.
internal final class LoginIDCollectStringsEmbeddedRepositoryImpl: LoginIDCollectStringsEmbeddedRepository {

    private let localInfo: (any LocalInfo)?

    internal init(localInfo: (any LocalInfo)?) {
        self.localInfo = localInfo
    }

    internal func fallbackToEmbedded<P: StringsParams>(params: P, map: [String: String]) -> LoginIDCollectStrings {
        let params = params as! LoginIDCollectStringsParams
        let isFidoPossible = localInfo?.isSystemFidoCapable ?? true
        let defaultStrings = LoginIDCollectStrings.default(
            loginIDTypes: params.loginIDTypes,
            isSystemFidoCapable: isFidoPossible
        )

        return LoginIDCollectStrings(
            title: map["title"] ?? defaultStrings.title,
            message: map["message"] ?? defaultStrings.message,
            placeholder: map["placeholder"] ?? defaultStrings.placeholder,
            cancel: map["cancel"] ?? defaultStrings.cancel,
            cta: map["cta"] ?? defaultStrings.cta,
            error: map["error"] ?? defaultStrings.error
        )
    }
}

/// Reads login ID collection strings from the server locale data source.
///
/// The server key path is selected from the collectable login ID types and passkey capability. Missing locale data
/// emits `nil`; unsupported login ID type sets and missing individual keys emit an empty or partial map so the embedded
/// repository can fill the result. Unavailable or unreadable persisted locale payloads are visible here as missing server
/// data; suppressed refresh failures may continue serving previously available data when a payload exists.
internal final class LoginIDCollectStringsServerRepositoryImpl: LoginIDCollectStringsServerRepository {
    private let localInfo: any LocalInfo
    private let serverLocaleProvider: any ServerLocaleDataSourceProvider
    private let prefix = ["steps", "login-id-collect"]

    internal init(localInfo: any LocalInfo, serverLocaleProvider: any ServerLocaleDataSourceProvider) {
        self.localInfo = localInfo
        self.serverLocaleProvider = serverLocaleProvider
    }

    internal func getStrings<P: StringsParams>(languageTag: LanguageTag, params: P) -> AsyncStream<[String: String]?> {
        guard let params = params as? LoginIDCollectStringsParams else {
            return AsyncStream { continuation in
                continuation.yield(nil)
                continuation.finish()
            }
        }
        let isFidoPossible = localInfo.isSystemFidoCapable
        let dataSourceStream = serverLocaleProvider.getDataSource(for: languageTag)

        return AsyncStream { continuation in
            let task = Task {
                for await dataSource in dataSourceStream {
                    guard let dataSource = dataSource else {
                        continuation.yield(nil)
                        continue
                    }

                    let loginIDTypes = Set(params.loginIDTypes.filter { $0 == .email || $0 == .phoneNumber || $0 == .userName })
                    let typeKey: String
                    switch loginIDTypes {
                    case [.email]: typeKey = "email"
                    case [.phoneNumber]: typeKey = "phoneNumber"
                    case [.userName]: typeKey = "userName"
                    case [.email, .phoneNumber]: typeKey = "emailOrPhoneNumber"
                    case [.email, .userName]: typeKey = "emailOrUserName"
                    case [.phoneNumber, .userName]: typeKey = "phoneNumberOrUserName"
                    case [.email, .phoneNumber, .userName]: typeKey = "emailOrPhoneNumberOrUserName"
                    default:
                        continuation.yield([:])
                        continue
                    }

                    let fetchFidoDependentString = { (key: String) -> String? in
                        if isFidoPossible {
                            return dataSource.getString(key: self.prefix[0], self.prefix[1], typeKey, key)
                        } else {
                            return dataSource.getString(key: self.prefix[0], self.prefix[1], typeKey, "no-biometrics", key)
                        }
                    }

                    var strings = [String: String]()
                    strings["title"] = fetchFidoDependentString("title")
                    strings["message"] = fetchFidoDependentString("message")
                    strings["placeholder"] = fetchFidoDependentString("placeholder")
                    strings["cancel"] = dataSource.getString(key: self.prefix[0], self.prefix[1], typeKey, "cancel")
                    strings["cta"] = dataSource.getString(key: self.prefix[0], self.prefix[1], typeKey, "cta")
                    strings["error"] = dataSource.getString(key: self.prefix[0], self.prefix[1], typeKey, "error")

                    continuation.yield(strings.compactMapValues { $0 })
                }
            }

            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}

/// Server repository used when locale data source setup is unavailable.
///
/// Emits an empty map so string resolution completes with embedded defaults.
internal struct LoginIDCollectStringsServerRepositoryEmptyFallback: LoginIDCollectStringsServerRepository {
    internal func getStrings<P: StringsParams>(languageTag: LanguageTag, params: P) -> AsyncStream<[String: String]?> {
        AsyncStream { continuation in
            continuation.yield([:])
            continuation.finish()
        }
    }
}
