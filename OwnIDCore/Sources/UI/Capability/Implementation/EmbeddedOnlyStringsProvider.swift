import Foundation

/// A ``StringsProvider`` that only uses embedded defaults without any server data.
///
/// Used when locale-backed provider setup fails. The stream yields the mapped embedded strings, finishes, and does not
/// react to language changes, server refreshes, or stored-locale changes.
internal final class EmbeddedOnlyStringsProviderAdapter<D: StringsData, P: StringsParams>: StringsProvider {

    private let factory: @Sendable (P) -> D

    internal init(factory: @escaping @Sendable (P) -> D) {
        self.factory = factory
    }

    internal func getStrings(params: P) -> AsyncStream<D?> {
        AsyncStream { continuation in
            continuation.yield(factory(params))
            continuation.finish()
        }
    }
}

extension EmbeddedOnlyStringsProviderAdapter: ErrorStringsProvider
where D == ErrorStrings, P == ErrorStringsParams {}

extension EmbeddedOnlyStringsProviderAdapter: LoginIDCollectStringsProvider
where D == LoginIDCollectStrings, P == LoginIDCollectStringsParams {}

extension EmbeddedOnlyStringsProviderAdapter: EmailVerificationStringsProvider
where D == EmailVerificationStrings, P == EmailVerificationStringsParams {}

extension EmbeddedOnlyStringsProviderAdapter: PhoneVerificationStringsProvider
where D == PhoneVerificationStrings, P == PhoneVerificationStringsParams {}

extension EmbeddedOnlyStringsProviderAdapter: BoostWidgetStringsProvider
where D == BoostWidgetStrings, P == BoostWidgetStringsParams {}
