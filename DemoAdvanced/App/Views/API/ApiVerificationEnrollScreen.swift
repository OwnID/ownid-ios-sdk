import OwnIDCore
import SwiftUI

struct ApiVerificationEnrollScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var viewModel: ApiViewModel
    @State private var code = ""

    var body: some View {
        let palette = Theme.palette(for: colorScheme)
        let screenState = viewModel.screenState
        let verificationState = viewModel.verificationState
        let hasAccessToken = screenState.accessToken != nil
        let isContextLocked = verificationState.isActive

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

                if verificationState.isActive {
                    Button("Clear State") {
                        viewModel.resetVerificationState()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    Button("Start Verification Challenge") {
                        viewModel.startVerificationChallenge()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(maxWidth: .infinity, alignment: .center)
                    .disabled(!screenState.canStartOperation)
                }

                if let challenge = verificationState.challenge {
                    let otpLength = challenge.methods.otp?.length ?? 4

                    ApiResponseView(title: nil, value: challenge.description)

                    HStack(spacing: 8) {
                        TextField("Code", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .demoInputFieldStyle()
                            .onChange(of: code) { newValue in
                                let normalizedCode = String(newValue.filter(\.isNumber).prefix(otpLength))
                                if normalizedCode != newValue {
                                    code = normalizedCode
                                }
                            }

                        Button("Verify") {
                            verificationState.completeWithCode(code)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .frame(height: 44)
                        .disabled(code.allSatisfy(\.isWhitespace))
                    }

                    HStack(spacing: 8) {
                        Button("Resend") { verificationState.resend() }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)

                        Button("Cancel") { verificationState.cancel() }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                    }
                }

                verificationState.proofToken.map { ApiResponseView(title: "Proof Token", value: String(describing: $0)) }
                verificationState.accessTokenResult.map { ApiResponseView(title: nil, value: String(describing: $0)) }
                verificationState.status.map { ApiResponseView(title: "Result", value: $0) }

                if verificationState.proofToken != nil {
                    Button("Enroll") {
                        viewModel.startVerificationEnrollment()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(maxWidth: .infinity, alignment: .center)
                    .disabled(!hasAccessToken)

                    if !hasAccessToken {
                        Text("Access token required for enrollment")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                verificationState.enrollResult.map { ApiResponseView(title: "Enroll Result", value: $0) }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .demoContentWidth()
        }
        .background(palette.background.ignoresSafeArea())
        .navigationTitle("APIs / Verification and Enroll")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewModel.verificationState.challenge?.challengeID) { _ in
            code = ""
        }
    }
}
