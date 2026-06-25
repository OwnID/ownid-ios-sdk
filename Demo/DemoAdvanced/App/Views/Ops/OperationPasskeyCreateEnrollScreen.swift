import OwnIDCore
import SwiftUI

struct OperationPasskeyCreateEnrollScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var viewModel: OperationViewModel

    var body: some View {
        let palette = Theme.palette(for: colorScheme)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Login ID")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    TextField(
                        "Email, phone number, or username",
                        text: Binding(
                            get: { viewModel.screenState.loginID },
                            set: { viewModel.onLoginIDChanged($0) }
                        )
                    )
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .keyboardType(viewModel.screenState.loginIDType?.keyboardType ?? .default)
                    .demoInputFieldStyle()
                }

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Login ID Type")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        NavigationLink {
                            OptionSelectionScreen(
                                title: "Login ID Type",
                                options: [nil, .email, .phoneNumber, .userName],
                                selectedOption: viewModel.screenState.loginIDType,
                                titleForOption: { $0?.displayTitle ?? "Auto" },
                                onSelect: viewModel.onLoginIDTypeSelected
                            )
                        } label: {
                            HStack(spacing: 8) {
                                Text(viewModel.screenState.loginIDType?.displayTitle ?? "Auto")
                                    .foregroundStyle(palette.onSurface)
                                    .lineLimit(1)

                                Spacer(minLength: 8)

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(palette.onSurfaceVariant)
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 44)
                            .frame(maxWidth: .infinity)
                            .background(palette.fieldBackground)
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                AccessTokenCheckbox(
                    isOn: viewModel.screenState.useAccessToken,
                    isEnabled: viewModel.screenState.accessToken != nil,
                    onToggle: viewModel.onUseAccessTokenChanged
                )

                Button("Start Passkey Create Operation") {
                    viewModel.startPasskeyCreateEnrollOperation()
                }
                .buttonStyle(PrimaryButtonStyle())
                .frame(maxWidth: .infinity, alignment: .center)
                .disabled(!viewModel.screenState.canStartOperation)

                if viewModel.screenState.accessToken == nil {
                    Text("Access token required for Passkey Enroll operation")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.center)
                        .padding(.top, 16)
                }

                Button("Start Passkey Enroll Operation") {
                    viewModel.startPasskeyEnrollOperation()
                }
                .buttonStyle(PrimaryButtonStyle())
                .frame(maxWidth: .infinity, alignment: .center)
                .disabled(viewModel.screenState.accessToken == nil || viewModel.screenState.attestationResponse == nil)

                LogView(log: viewModel.log)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .demoContentWidth()
        }
        .background(palette.background.ignoresSafeArea())
        .navigationTitle("Operations / Passkey Create and Enroll")
        .navigationBarTitleDisplayMode(.inline)
    }
}
