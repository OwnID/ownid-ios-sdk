import OwnIDCore
import OwnIDSwiftUI
import SwiftUI

struct BoostLoginScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var boostButtonPosition = OwnIDBoostButtonPosition.start
    @StateObject private var log = LogStore()

    let onPasswordLogin: (String, String) async throws -> Void

    private var isLoginDisabled: Bool {
        email.allSatisfy(\.isWhitespace) || password.count < 6 || isSubmitting
    }

    var body: some View {
        let palette = Theme.palette(for: colorScheme)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Text("widget position:")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Picker("widget position", selection: $boostButtonPosition) {
                        Text("Start").tag(OwnIDBoostButtonPosition.start)
                        Text("End").tag(OwnIDBoostButtonPosition.end)
                    }
                    .pickerStyle(.segmented)
                }

                Card {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .demoInputFieldStyle()

                    HStack(alignment: .center, spacing: 8) {
                        if boostButtonPosition == .start {
                            ownIDWidget
                            passwordField
                        } else {
                            passwordField
                            ownIDWidget
                        }
                    }

                    Button("Login") {
                        Task {
                            guard !email.allSatisfy(\.isWhitespace), password.count >= 6, !isSubmitting else { return }

                            isSubmitting = true
                            defer { isSubmitting = false }

                            do {
                                try await onPasswordLogin(email, password)
                            } catch {
                                log.add("Password Login -> Error: \(error.localizedDescription)")
                            }
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(maxWidth: .infinity, alignment: .center)
                    .disabled(isLoginDisabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                LogView(log: log)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .demoContentWidth()
        }
        .background(palette.background.ignoresSafeArea())
        .navigationTitle("Flows / Boost Login")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var ownIDWidget: some View {
        OwnIDLoginWidget(
            onLogin: { response in
                // Update the form with the login ID returned by the widget.
                email = response.loginID.id
                log.add("Boost Login Widget -> onLogin: \(response)")
            },
            loginID: email,
            onError: { error in
                log.add("Boost Login Widget -> onError: \(error)")
            },
            onCancel: { reason in
                log.add("Boost Login Widget -> onCancel: \(reason)")
            },
            position: boostButtonPosition,
            theme: Theme.ownIDWidgetTheme(for: colorScheme)
        )
        .frame(height: 44)
    }

    private var passwordField: some View {
        SecureField("Password", text: $password)
            .demoInputFieldStyle()
            .frame(maxWidth: .infinity)
    }
}
