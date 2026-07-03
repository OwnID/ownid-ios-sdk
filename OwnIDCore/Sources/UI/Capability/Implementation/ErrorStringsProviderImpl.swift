import Foundation

/// Maps server error-code keys into typed error strings and fills missing keys from embedded defaults.
internal final class ErrorStringsEmbeddedRepositoryImpl: ErrorStringsEmbeddedRepository {

    internal func fallbackToEmbedded<P: StringsParams>(params: P, map: [String: String]) -> ErrorStrings {
        let defaults = ErrorStrings.default
        return ErrorStrings(
            aborted: map[ErrorCode.aborted.value] ?? defaults.aborted,
            cancelNotSupported: map[ErrorCode.cancelNotSupported.value] ?? defaults.cancelNotSupported,
            deviceNotSupported: map[ErrorCode.deviceNotSupported.value] ?? defaults.deviceNotSupported,
            domElementNotFound: map[ErrorCode.domElementNotFound.value] ?? defaults.domElementNotFound,
            emptyLoginID: map[ErrorCode.emptyLoginID.value] ?? defaults.emptyLoginID,
            forbidden: map[ErrorCode.forbidden.value] ?? defaults.forbidden,
            integrationError: map[ErrorCode.integrationError.value] ?? defaults.integrationError,
            invalidArgument: map[ErrorCode.invalidArgument.value] ?? defaults.invalidArgument,
            invalidChallenge: map[ErrorCode.invalidChallenge.value] ?? defaults.invalidChallenge,
            loginIDTypeNotSupported: map[ErrorCode.loginIDTypeNotSupported.value] ?? defaults.loginIDTypeNotSupported,
            loginIDValidationFailed: map[ErrorCode.loginIDValidationFailed.value] ?? defaults.loginIDValidationFailed,
            loginWithPasswordFailed: map[ErrorCode.loginWithPasswordFailed.value] ?? defaults.loginWithPasswordFailed,
            maximumAttemptsReached: map[ErrorCode.maximumAttemptsReached.value] ?? defaults.maximumAttemptsReached,
            maximumChallengesReached: map[ErrorCode.maximumChallengesReached.value] ?? defaults.maximumChallengesReached,
            maximumResendAttemptsReached: map[ErrorCode.maximumResendAttemptsReached.value] ?? defaults.maximumResendAttemptsReached,
            missingCapabilityProvider: map[ErrorCode.missingCapabilityProvider.value] ?? defaults.missingCapabilityProvider,
            missingChannel: map[ErrorCode.missingChannel.value] ?? defaults.missingChannel,
            network: map[ErrorCode.network.value] ?? defaults.network,
            noApplicablePasskeys: map[ErrorCode.noApplicablePasskeys.value] ?? defaults.noApplicablePasskeys,
            notificationBlocked: map[ErrorCode.notificationBlocked.value] ?? defaults.notificationBlocked,
            oidcFailed: map[ErrorCode.oidcFailed.value] ?? defaults.oidcFailed,
            passkeyAlreadyRegistered: map[ErrorCode.passkeyAlreadyRegistered.value] ?? defaults.passkeyAlreadyRegistered,
            passkeyNotCreated: map[ErrorCode.passkeyNotCreated.value] ?? defaults.passkeyNotCreated,
            passkeysNotSupported: map[ErrorCode.passkeysNotSupported.value] ?? defaults.passkeysNotSupported,
            screensNotReady: map[ErrorCode.screensNotReady.value] ?? defaults.screensNotReady,
            sessionNotEstablished: map[ErrorCode.sessionNotEstablished.value] ?? defaults.sessionNotEstablished,
            timeout: map[ErrorCode.timeout.value] ?? defaults.timeout,
            unauthorized: map[ErrorCode.unauthorized.value] ?? defaults.unauthorized,
            unknown: map[ErrorCode.unknown.value] ?? defaults.unknown,
            userBlocked: map[ErrorCode.userBlocked.value] ?? defaults.userBlocked,
            userChanged: map[ErrorCode.userChanged.value] ?? defaults.userChanged,
            userNotFound: map[ErrorCode.userNotFound.value] ?? defaults.userNotFound,
            verificationCodeWrong: map[ErrorCode.verificationCodeWrong.value] ?? defaults.verificationCodeWrong,
            widgetAlreadyExists: map[ErrorCode.widgetAlreadyExists.value] ?? defaults.widgetAlreadyExists
        )
    }
}

/// Reads error strings from the server locale data source.
///
/// Missing locale data emits `nil`; missing individual error-code keys are omitted so the embedded repository can fill
/// them. Unavailable or unreadable persisted locale payloads are visible here as missing server data; suppressed refresh
/// failures may continue serving previously available data when a payload exists.
internal final class ErrorStringsServerRepositoryImpl: ErrorStringsServerRepository {
    private let serverLocaleProvider: any ServerLocaleDataSourceProvider
    private let prefix = ["errors"]

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
                    strings[ErrorCode.aborted.value] = dataSource.getString(key: self.prefix[0], ErrorCode.aborted.value)
                    strings[ErrorCode.cancelNotSupported.value] = dataSource.getString(
                        key: self.prefix[0],
                        ErrorCode.cancelNotSupported.value
                    )
                    strings[ErrorCode.deviceNotSupported.value] = dataSource.getString(
                        key: self.prefix[0],
                        ErrorCode.deviceNotSupported.value
                    )
                    strings[ErrorCode.domElementNotFound.value] = dataSource.getString(
                        key: self.prefix[0],
                        ErrorCode.domElementNotFound.value
                    )
                    strings[ErrorCode.emptyLoginID.value] = dataSource.getString(key: self.prefix[0], ErrorCode.emptyLoginID.value)
                    strings[ErrorCode.forbidden.value] = dataSource.getString(key: self.prefix[0], ErrorCode.forbidden.value)
                    strings[ErrorCode.integrationError.value] = dataSource.getString(key: self.prefix[0], ErrorCode.integrationError.value)
                    strings[ErrorCode.invalidArgument.value] = dataSource.getString(key: self.prefix[0], ErrorCode.invalidArgument.value)
                    strings[ErrorCode.invalidChallenge.value] = dataSource.getString(key: self.prefix[0], ErrorCode.invalidChallenge.value)
                    strings[ErrorCode.loginIDTypeNotSupported.value] = dataSource.getString(
                        key: self.prefix[0],
                        ErrorCode.loginIDTypeNotSupported.value
                    )
                    strings[ErrorCode.loginIDValidationFailed.value] = dataSource.getString(
                        key: self.prefix[0],
                        ErrorCode.loginIDValidationFailed.value
                    )
                    strings[ErrorCode.loginWithPasswordFailed.value] = dataSource.getString(
                        key: self.prefix[0],
                        ErrorCode.loginWithPasswordFailed.value
                    )
                    strings[ErrorCode.maximumAttemptsReached.value] = dataSource.getString(
                        key: self.prefix[0],
                        ErrorCode.maximumAttemptsReached.value
                    )
                    strings[ErrorCode.maximumChallengesReached.value] = dataSource.getString(
                        key: self.prefix[0],
                        ErrorCode.maximumChallengesReached.value
                    )
                    strings[ErrorCode.maximumResendAttemptsReached.value] = dataSource.getString(
                        key: self.prefix[0],
                        ErrorCode.maximumResendAttemptsReached.value
                    )
                    strings[ErrorCode.missingCapabilityProvider.value] = dataSource.getString(
                        key: self.prefix[0],
                        ErrorCode.missingCapabilityProvider.value
                    )
                    strings[ErrorCode.missingChannel.value] = dataSource.getString(key: self.prefix[0], ErrorCode.missingChannel.value)
                    strings[ErrorCode.network.value] = dataSource.getString(key: self.prefix[0], ErrorCode.network.value)
                    strings[ErrorCode.noApplicablePasskeys.value] = dataSource.getString(
                        key: self.prefix[0],
                        ErrorCode.noApplicablePasskeys.value
                    )
                    strings[ErrorCode.notificationBlocked.value] = dataSource.getString(
                        key: self.prefix[0],
                        ErrorCode.notificationBlocked.value
                    )
                    strings[ErrorCode.oidcFailed.value] = dataSource.getString(key: self.prefix[0], ErrorCode.oidcFailed.value)
                    strings[ErrorCode.passkeyAlreadyRegistered.value] = dataSource.getString(
                        key: self.prefix[0],
                        ErrorCode.passkeyAlreadyRegistered.value
                    )
                    strings[ErrorCode.passkeyNotCreated.value] = dataSource.getString(
                        key: self.prefix[0],
                        ErrorCode.passkeyNotCreated.value
                    )
                    strings[ErrorCode.passkeysNotSupported.value] = dataSource.getString(
                        key: self.prefix[0],
                        ErrorCode.passkeysNotSupported.value
                    )
                    strings[ErrorCode.screensNotReady.value] = dataSource.getString(key: self.prefix[0], ErrorCode.screensNotReady.value)
                    strings[ErrorCode.sessionNotEstablished.value] = dataSource.getString(
                        key: self.prefix[0],
                        ErrorCode.sessionNotEstablished.value
                    )
                    strings[ErrorCode.timeout.value] = dataSource.getString(key: self.prefix[0], ErrorCode.timeout.value)
                    strings[ErrorCode.unauthorized.value] = dataSource.getString(key: self.prefix[0], ErrorCode.unauthorized.value)
                    strings[ErrorCode.unknown.value] = dataSource.getString(key: self.prefix[0], ErrorCode.unknown.value)
                    strings[ErrorCode.userBlocked.value] = dataSource.getString(key: self.prefix[0], ErrorCode.userBlocked.value)
                    strings[ErrorCode.userChanged.value] = dataSource.getString(key: self.prefix[0], ErrorCode.userChanged.value)
                    strings[ErrorCode.userNotFound.value] = dataSource.getString(key: self.prefix[0], ErrorCode.userNotFound.value)
                    strings[ErrorCode.verificationCodeWrong.value] = dataSource.getString(
                        key: self.prefix[0],
                        ErrorCode.verificationCodeWrong.value
                    )
                    strings[ErrorCode.widgetAlreadyExists.value] = dataSource.getString(
                        key: self.prefix[0],
                        ErrorCode.widgetAlreadyExists.value
                    )

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
internal struct ErrorStringsServerRepositoryEmptyFallback: ErrorStringsServerRepository {
    internal func getStrings<P: StringsParams>(languageTag: LanguageTag, params: P) -> AsyncStream<[String: String]?> {
        AsyncStream { continuation in
            continuation.yield([:])
            continuation.finish()
        }
    }
}
