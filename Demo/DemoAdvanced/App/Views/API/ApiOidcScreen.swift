import OwnIDCore
import SwiftUI

struct ApiOidcScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var viewModel: ApiViewModel

    var body: some View {
        let palette = Theme.palette(for: colorScheme)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Text("Provider:")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Picker(
                        "Provider",
                        selection: Binding(
                            get: { viewModel.oidcState.provider },
                            set: { viewModel.onOIDCProviderSelected($0) }
                        )
                    ) {
                        Text("Apple").tag(SocialProviderID.apple)
                        Text("Google").tag(SocialProviderID.google)
                    }
                    .pickerStyle(.segmented)
                    .disabled(viewModel.oidcState.isActive)
                }

                AccessTokenCheckbox(
                    isOn: viewModel.screenState.mode == .accessToken,
                    isEnabled: viewModel.screenState.accessToken != nil && !viewModel.oidcState.isActive,
                    onToggle: { useAccessToken in
                        viewModel.onModeSelected(useAccessToken ? .accessToken : .loginID)
                    }
                )

                if viewModel.oidcState.hasState {
                    Button("Clear State") {
                        viewModel.resetOIDCState()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    Button("Start OIDC Challenge") {
                        viewModel.startOIDCChallenge()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(maxWidth: .infinity, alignment: .center)
                }

                if let challenge = viewModel.oidcState.challenge {
                    ApiResponseView(title: nil, value: String(describing: challenge))

                    Button(buttonTitle(for: viewModel.oidcState.provider)) {
                        viewModel.oidcState.authorize()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(maxWidth: .infinity, alignment: .center)

                    Button("Cancel") {
                        viewModel.oidcState.cancel()
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, alignment: .center)
                }

                viewModel.oidcState.result.map { ApiResponseView(title: nil, value: String(describing: $0)) }
                viewModel.oidcState.status.map { ApiResponseView(title: "Result", value: $0) }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .demoContentWidth()
        }
        .background(palette.background.ignoresSafeArea())
        .navigationTitle("APIs / OIDC")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func buttonTitle(for provider: SocialProviderID) -> String {
        switch provider {
        case .apple:
            return "Authorize with Apple"
        case .google:
            return "Authorize with Google"
        }
    }
}
