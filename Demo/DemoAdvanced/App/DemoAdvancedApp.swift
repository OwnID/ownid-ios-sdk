import GoogleSignIn
import OwnIDCore
import OwnIDSwiftUI
import SwiftUI
import UIKit

@main
struct DemoAdvancedApp: App {
    @StateObject private var authIntegration: CustomDemoAuthIntegration

    init() {
        let authIntegration = CustomDemoAuthIntegration(
            identityPlatform: DemoIdentityPlatform(baseURL: DemoConfiguration.demoIdentityBaseURL),
            sessionStorage: .shared
        )
        DemoAuthIntegrationProvider.integration = authIntegration
        _authIntegration = StateObject(wrappedValue: authIntegration)

        OwnID.logger { configuration in
            configuration.level = .verbose
        }

        if #unavailable(iOS 16.0) {
            UITableView.appearance().backgroundColor = .clear
        }

        OwnID.initializeFromJSON { configuration in
            configuration.json = DemoConfiguration.ownIDConfigJSON
        }

        OwnID.setProviders { registrar in
            registrar.demoIdentityProviders(authIntegration: authIntegration)
            registrar.signInWithGoogleProvider(configurationProvider: { serverClientID in
                GIDConfiguration(
                    // Google iOS OAuth client ID for the current DemoAdvanced bundle ID.
                    clientID: DemoConfiguration.googleIOSClientID,
                    serverClientID: serverClientID
                )
            })
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.layoutDirection, demoLayoutDirection)
                .ownIDTheme { colorScheme, theme in
                    let palette = Theme.palette(for: colorScheme)
                    theme.colors.primary = palette.primary
                    theme.colors.onPrimary = palette.onPrimary
                    theme.colors.surface = palette.cardBackground
                    theme.colors.iconButtonBorder = palette.border
                    theme.colors.onSurface = palette.onSurface
                    theme.colors.onSurfaceVariant = palette.onSurfaceVariant
                    theme.colors.fieldBackground = palette.fieldBackground
                }
                .onOpenURL { url in
                    _ = GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}

private var demoLayoutDirection: LayoutDirection {
    switch NSLocale.characterDirection(forLanguage: Locale.preferredLanguages.first ?? "en") {
    case .rightToLeft: return .rightToLeft
    default: return .leftToRight
    }
}

private enum DemoConfiguration {
    static let ownIDConfigJSON = stringValue(for: "OwnIDConfigJSON")
    static let demoIdentityBaseURL = URL(string: stringValue(for: "DemoIdentityBaseURL"))!
    static let googleIOSClientID = stringValue(for: "GoogleIOSClientID")

    private static func stringValue(for key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
    }
}
