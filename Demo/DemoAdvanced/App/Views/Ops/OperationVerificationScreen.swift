import OwnIDCore
import OwnIDSwiftUI
import SwiftUI

struct OperationVerificationScreen: View {
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
                        "Email or phone number",
                        text: Binding(
                            get: { viewModel.screenState.loginID },
                            set: { viewModel.onLoginIDChanged($0) }
                        )
                    )
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .keyboardType(viewModel.screenState.verificationLoginIDType.keyboardType)
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
                                options: [.email, .phoneNumber],
                                selectedOption: viewModel.screenState.verificationLoginIDType,
                                titleForOption: { $0.displayTitle },
                                onSelect: viewModel.onVerificationLoginIDTypeSelected
                            )
                        } label: {
                            HStack(spacing: 8) {
                                Text(viewModel.screenState.verificationLoginIDType.displayTitle)
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

                    VStack(alignment: .leading, spacing: 8) {
                        Text("UI Mode")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        NavigationLink {
                            OptionSelectionScreen(
                                title: "UI Mode",
                                options: OperationViewModel.UIMode.allCases,
                                selectedOption: viewModel.screenState.uiMode,
                                titleForOption: { $0.title },
                                onSelect: viewModel.onUIModeSelected
                            )
                        } label: {
                            HStack(spacing: 8) {
                                Text(viewModel.screenState.uiMode.title)
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

                Button("Start Verification Operation") {
                    viewModel.startVerificationOperation()
                }
                .buttonStyle(PrimaryButtonStyle())
                .frame(maxWidth: .infinity, alignment: .center)
                .disabled(!viewModel.screenState.canStartOperation)

                if viewModel.screenState.uiMode == .embedded,
                    viewModel.emailVerificationOperationUIController != nil || viewModel.phoneVerificationOperationUIController != nil
                {
                    Card(padding: EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)) {
                        if let controller = viewModel.emailVerificationOperationUIController {
                            OwnIDOperationView(operationUIController: controller)
                        } else if let controller = viewModel.phoneVerificationOperationUIController {
                            OwnIDOperationView(operationUIController: controller)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                LogView(log: viewModel.log)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .demoContentWidth()
        }
        .background(palette.background.ignoresSafeArea())
        .navigationTitle("Operations / Verification")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if viewModel.screenState.uiMode == .dialog,
                let controller = viewModel.emailVerificationOperationUIController
            {
                DemoOperationDialog(
                    operationUIController: controller,
                    onDismiss: {
                        viewModel.emailVerificationOperationUIController = nil
                    }
                )
                // OwnIDUIContainerController is single-use. Reset the dialog state
                // when a new SDK operation controller is presented.
                .id(controller.operationID)
            } else if viewModel.screenState.uiMode == .dialog,
                let controller = viewModel.phoneVerificationOperationUIController
            {
                DemoOperationDialog(
                    operationUIController: controller,
                    onDismiss: {
                        viewModel.phoneVerificationOperationUIController = nil
                    }
                )
                // OwnIDUIContainerController is single-use. Reset the dialog state
                // when a new SDK operation controller is presented.
                .id(controller.operationID)
            }
        }
        .animation(
            .default,
            value: viewModel.emailVerificationOperationUIController != nil || viewModel.phoneVerificationOperationUIController != nil
        )
    }
}
