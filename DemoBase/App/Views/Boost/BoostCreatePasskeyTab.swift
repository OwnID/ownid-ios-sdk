import OwnIDCore
import OwnIDSwiftUI
import SwiftUI

struct BoostCreatePasskeyTab: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var createPasskeyResponse: BoostFlowCreatePasskeyResponse?
    @StateObject private var log = LogStore()

    let onRegister: (String, String, String, String?) async throws -> Void

    private var isPasswordRequired: Bool {
        createPasskeyResponse?.ownIdData(forLoginID: email) == nil
    }

    private var isSubmitDisabled: Bool {
        name.allSatisfy(\.isWhitespace) || email.allSatisfy(\.isWhitespace) || (isPasswordRequired && password.count < 6) || isSubmitting
    }

    var body: some View {
        VStack(spacing: 16) {
            Card {
                TextField("Name", text: $name)
                    .demoInputFieldStyle()

                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .demoInputFieldStyle()

                HStack(alignment: .center, spacing: 8) {
                    OwnIDCreatePasskeyWidget(
                        onLogin: { response in
                            email = response.loginID.id
                            log.add("Boost Create Passkey -> onLogin: \(response)")
                        },
                        onNewPasskey: { response in
                            email = response.loginID.id
                            createPasskeyResponse = response
                            log.add("Boost Create Passkey -> onNewPasskey: \(response)")
                        },
                        onReset: {
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
                        theme: Theme.ownIDWidgetTheme(for: colorScheme)
                    )
                    .frame(height: DemoFormFieldStyle.height)

                    SecureField("Password", text: $password)
                        .demoInputFieldStyle()
                        .disabled(!isPasswordRequired)
                }

                Button("Submit") {
                    Task {
                        guard !isSubmitDisabled else { return }

                        isSubmitting = true
                        defer { isSubmitting = false }

                        do {
                            let ownIdData = createPasskeyResponse?.ownIdData(forLoginID: email)
                            let resolvedPassword = ownIdData == nil ? password : "SomeRandomLongAndCrypticPassword"
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

            LogView(log: log)
        }
    }
}
