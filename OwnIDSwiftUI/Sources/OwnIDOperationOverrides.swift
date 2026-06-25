import OwnIDCore
import SwiftUI

/// Local content overrides for app-hosted OwnID operation views.
///
/// Use the convenience modifiers on `View` when a SwiftUI subtree should render login ID collection, email
/// verification, or phone verification with app-provided content. Each builder receives the current operation state,
/// localized strings, an optional ``ErrorCode`` text provider, and a focus-readiness flag.
///
/// Override builders run on the main actor and own only rendering plus user-event wiring. Use callbacks from the
/// supplied UI state for user actions; do not complete or cancel the operation from unrelated app state. Leave a
/// builder unset to use the registered provider content for that operation. Built-in content owns its visible busy
/// indicators, error display, resend visibility, and one-time focus behavior; custom content owns those same UI choices
/// for the operation it replaces.
public struct OwnIDOperationOverrides: @unchecked Sendable {
    /// Custom content for login ID collection.
    public var loginIDCollectContent:
        (@MainActor (LoginIDCollectUIState, LoginIDCollectStrings, ((ErrorCode) -> String)?, Bool) -> AnyView)? = nil
    /// Custom content for email verification.
    public var emailVerificationContent:
        (@MainActor (EmailVerificationUIState, EmailVerificationStrings, ((ErrorCode) -> String)?, Bool) -> AnyView)? = nil
    /// Custom content for phone verification.
    public var phoneVerificationContent:
        (@MainActor (PhoneVerificationUIState, PhoneVerificationStrings, ((ErrorCode) -> String)?, Bool) -> AnyView)? = nil

    /// Creates operation-content overrides.
    ///
    /// Leave a builder as `nil` to keep the SDK-provided content for that operation.
    public init(
        loginIDCollectContent:
            (@MainActor (LoginIDCollectUIState, LoginIDCollectStrings, ((ErrorCode) -> String)?, Bool) -> AnyView)? = nil,
        emailVerificationContent:
            (@MainActor (EmailVerificationUIState, EmailVerificationStrings, ((ErrorCode) -> String)?, Bool) -> AnyView)? = nil,
        phoneVerificationContent:
            (@MainActor (PhoneVerificationUIState, PhoneVerificationStrings, ((ErrorCode) -> String)?, Bool) -> AnyView)? = nil
    ) {
        self.loginIDCollectContent = loginIDCollectContent
        self.emailVerificationContent = emailVerificationContent
        self.phoneVerificationContent = phoneVerificationContent
    }
}

private struct OwnIDOperationOverridesKey: EnvironmentKey {
    fileprivate static let defaultValue = OwnIDOperationOverrides()
}

extension EnvironmentValues {
    /// Operation-content overrides available to OwnID operation views in this SwiftUI environment.
    public var ownIDOperationOverrides: OwnIDOperationOverrides {
        get { self[OwnIDOperationOverridesKey.self] }
        set { self[OwnIDOperationOverridesKey.self] = newValue }
    }
}

extension View {
    /// Replaces login-ID-collection content used by ``OwnIDOperationView`` instances in this SwiftUI subtree.
    ///
    /// The builder receives the current operation state, localized strings, an optional provider from ``ErrorCode`` to
    /// display text, and `isReadyForInitialFocus`, which becomes `true` when the surrounding presentation is ready for
    /// one-time initial text input focus. Invoke ``LoginIDCollectUIState/onLoginIDChange``,
    /// ``LoginIDCollectUIState/onContinue``, and ``LoginIDCollectUIState/onCancel`` for user actions; the SDK owns
    /// validation and settlement.
    public func withLoginIDCollectContent<Content: View>(
        _ builder: @escaping @MainActor (LoginIDCollectUIState, LoginIDCollectStrings, ((ErrorCode) -> String)?, Bool) -> Content
    ) -> some View {
        modifier(
            OwnIDOverrideModifier { current in
                var next = current
                next.loginIDCollectContent = { state, strings, errorTextProvider, isReadyForInitialFocus in
                    AnyView(builder(state, strings, errorTextProvider, isReadyForInitialFocus))
                }
                return next
            }
        )
    }

    /// Replaces email-verification content used by ``OwnIDOperationView`` instances in this SwiftUI subtree.
    ///
    /// The builder receives the current operation state, localized strings, an optional provider from ``ErrorCode`` to
    /// display text, and `isReadyForInitialFocus`, which becomes `true` when the surrounding presentation is ready for
    /// one-time initial text input focus. Invoke callbacks from ``EmailVerificationUIState`` for code entry, resend,
    /// cancel, and "not you" actions; the SDK owns challenge state and settlement.
    public func withEmailVerificationContent<Content: View>(
        _ builder: @escaping @MainActor (EmailVerificationUIState, EmailVerificationStrings, ((ErrorCode) -> String)?, Bool) -> Content
    ) -> some View {
        modifier(
            OwnIDOverrideModifier { current in
                var next = current
                next.emailVerificationContent = { state, strings, errorTextProvider, isReadyForInitialFocus in
                    AnyView(builder(state, strings, errorTextProvider, isReadyForInitialFocus))
                }
                return next
            }
        )
    }

    /// Replaces phone-verification content used by ``OwnIDOperationView`` instances in this SwiftUI subtree.
    ///
    /// The builder receives the current operation state, localized strings, an optional provider from ``ErrorCode`` to
    /// display text, and `isReadyForInitialFocus`, which becomes `true` when the surrounding presentation is ready for
    /// one-time initial text input focus. Invoke callbacks from ``PhoneVerificationUIState`` for code entry, resend,
    /// cancel, and "not you" actions; the SDK owns challenge state and settlement.
    public func withPhoneVerificationContent<Content: View>(
        _ builder: @escaping @MainActor (PhoneVerificationUIState, PhoneVerificationStrings, ((ErrorCode) -> String)?, Bool) -> Content
    ) -> some View {
        modifier(
            OwnIDOverrideModifier { current in
                var next = current
                next.phoneVerificationContent = { state, strings, errorTextProvider, isReadyForInitialFocus in
                    AnyView(builder(state, strings, errorTextProvider, isReadyForInitialFocus))
                }
                return next
            }
        )
    }
}

private struct OwnIDOverrideModifier: ViewModifier {
    @Environment(\.ownIDOperationOverrides) private var overrides
    private let mutate: (OwnIDOperationOverrides) -> OwnIDOperationOverrides

    fileprivate init(mutate: @escaping (OwnIDOperationOverrides) -> OwnIDOperationOverrides) {
        self.mutate = mutate
    }

    fileprivate func body(content: Content) -> some View {
        content.environment(\.ownIDOperationOverrides, mutate(overrides))
    }
}
