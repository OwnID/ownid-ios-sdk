import OwnIDCore
import OwnIDSwiftUI
import SwiftUI

struct BoostLoginTab: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @StateObject private var log = LogStore()

    let onPasswordLogin: (String, String) async throws -> Void

    var body: some View {
        let isEmailBlank = email.allSatisfy(\.isWhitespace)

        VStack(spacing: 16) {
            Card {
                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .demoInputFieldStyle()

                HStack(alignment: .center, spacing: 8) {
                    OwnIDLoginWidget(
                        onLogin: { response in
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
                        theme: Theme.ownIDWidgetTheme(for: colorScheme)
                    )
                    .frame(height: DemoFormFieldStyle.height)

                    SecureField("Password", text: $password)
                        .demoInputFieldStyle()
                }

                Button("Login") {
                    Task {
                        guard !isEmailBlank, password.count >= 6, !isSubmitting else { return }

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
                .disabled(isEmailBlank || password.count < 6 || isSubmitting)
            }

            LogView(log: log)
        }
    }
}
