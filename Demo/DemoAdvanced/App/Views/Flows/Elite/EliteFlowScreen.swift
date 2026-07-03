import SwiftUI

struct EliteFlowScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel = EliteFlowViewModel()

    var body: some View {
        let palette = Theme.palette(for: colorScheme)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Button("Start Elite Flow") {
                    viewModel.startEliteFlow()
                }
                .buttonStyle(PrimaryButtonStyle())
                .frame(maxWidth: .infinity, alignment: .center)
                .disabled(viewModel.isRunning)

                LogView(log: viewModel.log)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .demoContentWidth()
        }
        .background(palette.background.ignoresSafeArea())
        .navigationTitle("Flows / Elite")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: pendingRegistrationBinding) { registration in
            EliteRegistrationSheet(registration: registration) { name in
                await viewModel.completeRegistration(name: name)
            }
        }
    }

    private var pendingRegistrationBinding: Binding<EliteFlowViewModel.PendingRegistration?> {
        Binding(
            get: { viewModel.pendingRegistration },
            set: { if $0 == nil { viewModel.cancelRegistration() } }
        )
    }
}

private struct EliteRegistrationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    let registration: EliteFlowViewModel.PendingRegistration
    let onSubmit: (String) async -> Void

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Complete registration")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Card {
                TextField("Email", text: .constant(registration.email))
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .demoInputFieldStyle()
                    .disabled(true)

                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)
                    .demoInputFieldStyle()
            }

            Button("Create user") {
                Task { await onSubmit(trimmedName) }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(trimmedName.allSatisfy(\.isWhitespace))

            Button("Cancel") { dismiss() }
                .font(.system(size: 17, weight: .semibold))
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .frame(maxWidth: 420)
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, 20)
        .presentationStyle()
    }
}

extension View {
    @ViewBuilder
    fileprivate func presentationStyle() -> some View {
        if #available(iOS 16.0, *) {
            presentationDetents([.height(340), .medium])
                .presentationDragIndicator(.visible)
        } else {
            self
        }
    }
}
