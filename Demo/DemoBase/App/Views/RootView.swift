import SwiftUI

struct RootView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var sessionStorage = DemoUserSessionStorage.shared

    var body: some View {
        NavigationView {
            if let session = sessionStorage.currentSession {
                CurrentUserScreen(
                    session: session,
                    loadCurrentUser: { session in
                        try await DemoBaseApp.identityPlatform.loadCurrentUser(session: session)
                    },
                    onLogout: DemoBaseApp.identityPlatform.logout
                )
            } else {
                HomeScreen(
                    onPasswordLogin: { email, password in
                        try await DemoBaseApp.identityPlatform.passwordLogin(email: email, password: password)
                    },
                    onRegister: { name, email, password, ownIdData in
                        try await DemoBaseApp.identityPlatform.registerAndSaveSession(
                            name: name,
                            email: email,
                            password: password,
                            ownIdData: ownIdData
                        )
                    }
                )
            }
        }
        .navigationViewStyle(.stack)
        .id(sessionStorage.currentSession?.token ?? "guest")
        .tint(Theme.palette(for: colorScheme).primary)
        .accentColor(Theme.palette(for: colorScheme).primary)
    }
}

struct HomeScreen: View {
    @Environment(\.colorScheme) private var colorScheme

    let onPasswordLogin: (String, String) async throws -> Void
    let onRegister: (String, String, String, String?) async throws -> Void

    var body: some View {
        let palette = Theme.palette(for: colorScheme)

        ScrollView {
            VStack(spacing: 48) {
                DemoHeaderView(title: "\((Bundle.main.bundleIdentifier!.components(separatedBy: ".").last)!.uppercased()): OwnID Demo")

                VStack(spacing: 16) {
                    NavigationLink(
                        destination: BoostFlowScreen(onPasswordLogin: onPasswordLogin, onRegister: onRegister)
                    ) {
                        ModeCard(title: "Boost Flow")
                    }
                    .buttonStyle(.plain)

                    NavigationLink(destination: EliteFlowScreen()) {
                        ModeCard(title: "Elite Flow")
                    }
                    .buttonStyle(.plain)

                    NavigationLink(destination: HeadlessScreen()) {
                        ModeCard(title: "Headless")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .demoContentWidth()
        }
        .background(palette.background.ignoresSafeArea())
        .navigationBarHidden(true)
    }
}

private struct ModeCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String

    var body: some View {
        let palette = Theme.palette(for: colorScheme)

        Text(title)
            .font(.system(size: 19, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 112)
            .foregroundStyle(palette.onSurface)
            .background(palette.cardBackground)
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(palette.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
