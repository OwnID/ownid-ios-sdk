import OwnIDCore
import SwiftUI

struct ApiDiscoverLoginScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var viewModel: ApiViewModel

    var body: some View {
        let palette = Theme.palette(for: colorScheme)
        let screenState = viewModel.screenState
        let discoverState = viewModel.discoverState
        let loginState = viewModel.loginState

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card {
                    Text("Discover")
                        .font(.headline)

                    TextField(
                        "Email or phone number",
                        text: Binding(
                            get: { screenState.loginID },
                            set: { viewModel.onLoginIDChanged($0) }
                        )
                    )
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .keyboardType(screenState.loginIDType.keyboardType)
                    .demoInputFieldStyle()

                    HStack(spacing: 12) {
                        Text("Login ID Type:")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Picker(
                            "Login ID Type",
                            selection: Binding(
                                get: { screenState.loginIDType },
                                set: { viewModel.onLoginIDTypeSelected($0) }
                            )
                        ) {
                            Text(OwnIDCore.LoginIDType.email.displayTitle).tag(OwnIDCore.LoginIDType.email)
                            Text(OwnIDCore.LoginIDType.phoneNumber.displayTitle).tag(OwnIDCore.LoginIDType.phoneNumber)
                        }
                        .pickerStyle(.segmented)
                    }

                    if discoverState.hasState {
                        Button("Clear State") {
                            viewModel.resetDiscoverState()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        Button("Start Discover") {
                            viewModel.startDiscoverLoginDiscover()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .frame(maxWidth: .infinity, alignment: .center)
                        .disabled(screenState.isLoginIDBlank)
                    }

                    discoverState.discoverResponse.map { ApiResponseView(title: nil, value: String(describing: $0)) }
                    discoverState.discoverStatus.map { ApiResponseView(title: "Discover Error", value: $0) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Card {
                    Text("Login")
                        .font(.headline)

                    if let accessToken = screenState.accessToken {
                        ApiResponseView(title: "Access Token", value: String(describing: accessToken))
                    } else {
                        Text("Access token required for Login")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if loginState.hasState {
                        Button("Clear State") {
                            viewModel.resetLoginState()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        Button("Start Login") {
                            viewModel.startDiscoverLoginLogin()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .frame(maxWidth: .infinity, alignment: .center)
                        .disabled(screenState.accessToken == nil)
                    }

                    loginState.loginResponse.map { ApiResponseView(title: "Login Result", value: String(describing: $0)) }
                    loginState.loginStatus.map { ApiResponseView(title: "Login Error", value: $0) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .demoContentWidth()
        }
        .background(palette.background.ignoresSafeArea())
        .navigationTitle("APIs / Discover and Login")
        .navigationBarTitleDisplayMode(.inline)
    }
}
