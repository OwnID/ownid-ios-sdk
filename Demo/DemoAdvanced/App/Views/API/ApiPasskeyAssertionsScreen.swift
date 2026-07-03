import OwnIDCore
import SwiftUI

struct ApiPasskeyAssertionsScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var viewModel: ApiViewModel

    var body: some View {
        let palette = Theme.palette(for: colorScheme)
        let screenState = viewModel.screenState
        let passkeyAssertionsState = viewModel.passkeyAssertionsState
        let hasAccessToken = screenState.accessToken != nil
        let isContextLocked = passkeyAssertionsState.isActive

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Text("Mode:")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Picker(
                        "Mode",
                        selection: Binding(
                            get: { screenState.mode },
                            set: { viewModel.onModeSelected($0) }
                        )
                    ) {
                        Text(ApiViewModel.Mode.loginID.rawValue).tag(ApiViewModel.Mode.loginID)
                        Text(ApiViewModel.Mode.accessToken.rawValue).tag(ApiViewModel.Mode.accessToken)
                    }
                    .pickerStyle(.segmented)
                    .disabled(isContextLocked || !hasAccessToken)
                }

                if screenState.mode == .loginID {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Login ID")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

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
                        .disabled(isContextLocked)
                    }
                }

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
                    .disabled(isContextLocked)
                }

                if passkeyAssertionsState.isActive {
                    Button("Clear State") {
                        viewModel.resetPasskeyAssertionsState()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    Button("Start Passkey Assertion Challenge") {
                        viewModel.startPasskeyAssertionChallenge()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(maxWidth: .infinity, alignment: .center)
                }

                if let assertionOptions = passkeyAssertionsState.assertionOptions {
                    ApiResponseView(title: nil, value: assertionOptions.description)

                    Button("Run Passkey Assertion") {
                        passkeyAssertionsState.runAssertion()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(maxWidth: .infinity, alignment: .center)
                    .disabled(passkeyAssertionsState.assertionResult != nil)

                    HStack(spacing: 8) {
                        Button("Cancel Assertion") {
                            passkeyAssertionsState.cancelAssertion()
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)

                        Button("Verify Assertion") {
                            if let assertionResult = passkeyAssertionsState.assertionResult {
                                passkeyAssertionsState.verifyAssertion(assertionResult)
                            }
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                        .disabled(passkeyAssertionsState.assertionResult == nil || passkeyAssertionsState.accessTokenResult != nil)
                    }
                }

                passkeyAssertionsState.assertionResult.map { ApiResponseView(title: nil, value: String(describing: $0)) }
                passkeyAssertionsState.accessTokenResult.map { ApiResponseView(title: nil, value: String(describing: $0)) }
                passkeyAssertionsState.status.map { ApiResponseView(title: "Result", value: $0) }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .demoContentWidth()
        }
        .background(palette.background.ignoresSafeArea())
        .navigationTitle("APIs / Passkey Assertions")
        .navigationBarTitleDisplayMode(.inline)
    }
}
