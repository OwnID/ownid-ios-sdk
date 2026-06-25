import OwnIDCore
import SwiftUI

struct ApiPasskeyCreateEnrollScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var viewModel: ApiViewModel

    var body: some View {
        let palette = Theme.palette(for: colorScheme)
        let screenState = viewModel.screenState
        let passkeyCreateState = viewModel.passkeyCreateState
        let hasAccessToken = screenState.accessToken != nil
        let isContextLocked = passkeyCreateState.isActive

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

                if passkeyCreateState.isActive {
                    Button("Clear State") {
                        viewModel.resetPasskeyCreateState()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    Button("Start Passkey Create Challenge") {
                        viewModel.startPasskeyCreateChallenge()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(maxWidth: .infinity, alignment: .center)
                    .disabled(!screenState.canStartOperation)
                }

                if let attestationOptions = passkeyCreateState.attestationOptions {
                    ApiResponseView(title: nil, value: attestationOptions.description)

                    Button("Create Passkey") {
                        passkeyCreateState.createPasskey()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(maxWidth: .infinity, alignment: .center)
                    .disabled(passkeyCreateState.attestationResult != nil)

                    HStack(spacing: 8) {
                        Button("Cancel Passkey") {
                            passkeyCreateState.cancelPasskey()
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)

                        Button("Verify Attestation") {
                            if let attestationResult = passkeyCreateState.attestationResult {
                                passkeyCreateState.verifyAttestation(attestationResult)
                            }
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                        .disabled(passkeyCreateState.attestationResult == nil || passkeyCreateState.attestationResponse != nil)
                    }
                }

                passkeyCreateState.attestationResult.map { ApiResponseView(title: nil, value: String(describing: $0)) }
                passkeyCreateState.attestationResponse.map { ApiResponseView(title: nil, value: String(describing: $0)) }
                passkeyCreateState.status.map { ApiResponseView(title: "Result", value: $0) }

                if passkeyCreateState.attestationResponse != nil {
                    Button("Enroll Passkey") {
                        viewModel.startPasskeyEnrollment()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(maxWidth: .infinity, alignment: .center)
                    .disabled(!hasAccessToken || passkeyCreateState.enrollResult != nil)

                    if !hasAccessToken {
                        Text("Access token required for enrollment")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                passkeyCreateState.enrollResult.map { ApiResponseView(title: "Enroll Result", value: $0) }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .demoContentWidth()
        }
        .background(palette.background.ignoresSafeArea())
        .navigationTitle("APIs / Passkey Create and Enroll")
        .navigationBarTitleDisplayMode(.inline)
    }
}
