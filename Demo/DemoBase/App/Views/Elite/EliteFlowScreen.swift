import SwiftUI

struct EliteFlowScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = EliteFlowViewModel()

    var body: some View {
        let palette = Theme.palette(for: colorScheme)

        ScrollView {
            VStack(spacing: 16) {
                DemoHeaderView(title: "Elite Flow", onBack: { dismiss() })

                Button("Start Elite Flow") {
                    viewModel.start()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(viewModel.isRunning)

                LogView(log: viewModel.log)

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .demoContentWidth()
        }
        .background(palette.background.ignoresSafeArea())
        .navigationBarHidden(true)
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
            .disabled(trimmedName.isEmpty)

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
