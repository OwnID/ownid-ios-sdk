import OwnIDCore
import OwnIDSwiftUI
import SwiftUI

struct BoostCreatePasskeyScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var createPasskeyResponse: BoostFlowCreatePasskeyResponse?
    @State private var boostButtonPosition = OwnIDBoostButtonPosition.start
    @StateObject private var log = LogStore()

    let onRegister: (String, String, String, String?) async throws -> Void

    private var ownIdData: String? {
        // Submit ownIdData only when the current email still matches the passkey response.
        guard let response = createPasskeyResponse, email == response.loginID.id else { return nil }
        return response.ownIdData
    }

    private var resolvedPassword: String {
        // When ownIdData is present, the demo flow uses a generated password instead of the typed one.
        ownIdData == nil ? password : "SomeRandomLongAndCrypticPassword"
    }

    private var isSubmitDisabled: Bool {
        name.allSatisfy(\.isWhitespace) || email.allSatisfy(\.isWhitespace) || (ownIdData == nil && password.count < 6) || isSubmitting
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
                    TextField("Name", text: $name)
                        .demoInputFieldStyle()

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

                    Button("Submit") {
                        Task {
                            guard !isSubmitDisabled else { return }

                            isSubmitting = true
                            defer { isSubmitting = false }

                            do {
                                // Register the user with either the typed password or the generated demo password.
                                try await onRegister(name, email, resolvedPassword, ownIdData)
                                createPasskeyResponse = nil
                            } catch {
                                log.add("Register failed: \(error.localizedDescription)")
                            }
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(maxWidth: .infinity, alignment: .center)
                    .disabled(isSubmitDisabled)
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
        .navigationTitle("Flows / Boost Create Passkey")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var ownIDWidget: some View {
        OwnIDCreatePasskeyWidget(
            onLogin: { response in
                // Update the form with the login ID returned by the widget.
                email = response.loginID.id
                log.add("Boost Create Passkey -> onLogin: \(response)")
            },
            onNewPasskey: { response in
                // Update the form and keep the passkey response for submit.
                email = response.loginID.id
                createPasskeyResponse = response
                log.add("Boost Create Passkey -> onNewPasskey: \(response)")
            },
            onReset: {
                // Clear the cached passkey response when the widget resets.
                createPasskeyResponse = nil
                log.add("Boost Create Passkey -> onReset")
            },
            loginID: email,
            onError: { error in
                log.add("Boost Create Passkey -> onError: \(error)")
            },
            onCancel: { reason in
                log.add("Boost Create Passkey -> onCancel: \(reason)")
            },
            position: boostButtonPosition,
            theme: Theme.ownIDWidgetTheme(for: colorScheme)
        )
        .frame(height: 44)
    }

    private var passwordField: some View {
        SecureField("Password", text: $password)
            // When ownIdData is present, the demo no longer asks for a password.
            .demoInputFieldStyle()
            .frame(maxWidth: .infinity)
            .disabled(ownIdData != nil)
    }
}
