import OwnIDCore
import SwiftUI

struct CurrentUserScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var loadState: LoadState = .loading
    @StateObject private var viewModel = CurrentUserViewModel()

    let session: DemoUserSession
    let loadCurrentUser: (DemoUserSession) async throws -> DemoUser
    let onLogout: () -> Void

    private enum LoadState {
        case loading
        case success(DemoUser)
        case failure(String)
    }

    var body: some View {
        let palette = Theme.palette(for: colorScheme)

        ScrollView {
            VStack(alignment: .center, spacing: 20) {
                DemoHeaderView(title: "Current User")

                switch loadState {
                case .loading:
                    ProgressView()
                        .padding(.top, 16)
                case .success(let currentUser):
                    CurrentUserCard(currentUser: currentUser)
                        .frame(maxWidth: .infinity)

                    PasskeyEnrollAction(
                        accessToken: session.accessToken,
                        isRunning: viewModel.isRunning,
                        onStart: viewModel.startPasskeyEnrollFlow
                    )
                case .failure(let message):
                    Text(message)
                        .font(.body)
                        .foregroundStyle(Color.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 16)
                }

                Button("Logout", action: onLogout)
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 8)

                LogView(log: viewModel.log)

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .demoContentWidth()
        }
        .background(palette.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .task {
            loadState = .loading
            do {
                loadState = .success(try await loadCurrentUser(session))
            } catch {
                loadState = .failure(error.localizedDescription)
            }
        }
    }
}

private struct PasskeyEnrollAction: View {
    let accessToken: AccessToken?
    let isRunning: Bool
    let onStart: (AccessToken?) -> Void

    var body: some View {
        VStack(spacing: 8) {
            if accessToken == nil {
                Text("Access token required for Passkey Enroll Flow")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            Button("Start Passkey Enroll Flow") {
                onStart(accessToken)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(accessToken == nil || isRunning)
        }
    }
}

private struct CurrentUserCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let currentUser: DemoUser

    var body: some View {
        let palette = Theme.palette(for: colorScheme)

        Card {
            Text("Current User:")
                .font(.title2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(palette.onSurface)

            Text("Name: \(currentUser.name ?? "")")
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(palette.onSurface)

            Text("Email: \(currentUser.email)")
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(palette.onSurface)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
