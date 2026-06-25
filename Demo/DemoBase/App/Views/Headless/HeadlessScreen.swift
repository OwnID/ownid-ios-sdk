import OwnIDCore
import SwiftUI

struct HeadlessScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = HeadlessViewModel()
    @State private var otpCode = ""
    @State private var debounceUnlocked = false

    var body: some View {
        let palette = Theme.palette(for: colorScheme)
        let flowState = viewModel.screenState.flowState
        let isLoading = flowState.isLoading
        let email = Binding(
            get: { viewModel.screenState.email },
            set: viewModel.onEmailChanged
        )

        ScrollView {
            VStack(spacing: 16) {
                DemoHeaderView(title: "Headless", onBack: { dismiss() })

                Card {
                    TextField("Email", text: email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .demoInputFieldStyle()
                        .disabled(flowState.isActive)

                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.vertical, 12)
                    } else {
                        Button("Start Headless Flow") {
                            otpCode = ""
                            viewModel.start()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .frame(maxWidth: 220, alignment: .center)
                        .frame(maxWidth: .infinity)
                        .disabled(viewModel.screenState.email.isEmpty || flowState.isActive)
                    }
                }

                if case .emailVerification(let challenge, let resendCount, let resendAvailableAt, let error, let busy) = flowState {
                    let otpLength = challenge.methods.otp?.length
                    let resendPolicy = challenge.resendPolicy
                    let otpCodeBinding = Binding(
                        get: { otpCode },
                        set: { value in
                            let digits = value.filter { $0.isNumber }
                            otpCode = otpLength.map { String(digits.prefix($0)) } ?? digits
                        }
                    )
                    let canResend = !busy && resendPolicy.allow && resendCount < resendPolicy.attempts && debounceUnlocked

                    Card {
                        TextField("Email OTP", text: otpCodeBinding)
                            .keyboardType(.numberPad)
                            .demoInputFieldStyle()

                        if let error {
                            Text(error.localizedMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if busy {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                            .padding(.top, 4)
                        }

                        Button("Verify Email OTP") {
                            viewModel.completeEmailVerification(otpCode)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .frame(maxWidth: 220, alignment: .center)
                        .frame(maxWidth: .infinity)
                        .disabled(busy || otpCode.isEmpty || (otpLength.map { requiredLength in otpCode.count != requiredLength } ?? false))

                        Button("Resend OTP") {
                            viewModel.resendEmailVerification()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .frame(maxWidth: 220, alignment: .center)
                        .frame(maxWidth: .infinity)
                        .disabled(!canResend)

                        Button("Cancel Email Verification") {
                            viewModel.cancelEmailVerification()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .frame(maxWidth: 220, alignment: .center)
                        .frame(maxWidth: .infinity)
                        .disabled(busy)
                    }
                    .task(id: challenge.challengeID.value) {
                        otpCode = ""
                    }
                    .task(id: resendAvailableAt) {
                        debounceUnlocked = false
                        let delay = resendAvailableAt - ProcessInfo.processInfo.systemUptime
                        if delay > 0 {
                            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        }
                        debounceUnlocked = true
                    }
                }

                LogView(log: viewModel.log)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .demoContentWidth()
        }
        .background(palette.background.ignoresSafeArea())
        .navigationBarHidden(true)
    }
}
