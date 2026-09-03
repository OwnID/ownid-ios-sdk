import OwnIDCore
import OwnIDSwiftUI
import SwiftUI

struct OperationLoginIdCollectScreen: View {
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

                Button("Start Login ID Collect Operation") {
                    viewModel.startLoginIdCollectOperation()
                }
                .buttonStyle(PrimaryButtonStyle())
                .frame(maxWidth: .infinity, alignment: .center)

                if viewModel.screenState.uiMode == .embedded,
                    let operationUIController = viewModel.loginIDOperationUIController
                {
                    Card(padding: EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)) {
                        OwnIDOperationView(operationUIController: operationUIController)
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
        .navigationTitle("Operations / Login ID Collect")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if viewModel.screenState.uiMode == .dialog,
                let operationUIController = viewModel.loginIDOperationUIController
            {
                DemoOperationDialog(
                    operationUIController: operationUIController,
                    onDismiss: {
                        viewModel.loginIDOperationUIController = nil
                    }
                )
                // OwnIDUIContainerController is single-use. Reset the dialog state
                // when a new SDK operation controller is presented.
                .id(operationUIController.operationID)
            }
        }
        .animation(.default, value: viewModel.loginIDOperationUIController != nil)
    }
}
