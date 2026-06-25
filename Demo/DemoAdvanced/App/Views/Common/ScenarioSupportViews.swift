import OwnIDCore
import SwiftUI
import UIKit

extension OwnIDCore.LoginIDType {
    var displayTitle: String {
        switch self {
        case .email: return "Email"
        case .phoneNumber: return "Phone Number"
        case .userName: return "Username"
        case .credentialID: return "Credential ID"
        default: return rawValue
        }
    }

    var keyboardType: UIKeyboardType {
        switch self {
        case .email: return .emailAddress
        case .phoneNumber: return .phonePad
        default: return .default
        }
    }
}

struct OptionSelectionScreen<Option>: View
where Option: Hashable {
    @Environment(\.presentationMode) private var presentationMode

    let title: String
    let options: [Option]
    let selectedOption: Option
    let titleForOption: (Option) -> String
    let onSelect: (Option) -> Void

    var body: some View {
        List(options, id: \.self) { option in
            Button {
                presentationMode.wrappedValue.dismiss()
                Task { @MainActor in
                    onSelect(option)
                }
            } label: {
                HStack {
                    Text(titleForOption(option))
                    Spacer()
                    if option == selectedOption {
                        Image(systemName: "checkmark")
                    }
                }
            }
            .foregroundStyle(.primary)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AccessTokenCheckbox: View {
    let isOn: Bool
    let isEnabled: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        Toggle(
            "Use Access token",
            isOn: Binding(
                get: { isOn },
                set: onToggle
            )
        )
        .toggleStyle(.switch)
        .fixedSize()
        .frame(maxWidth: .infinity, alignment: .center)
        .disabled(!isEnabled)
    }
}

struct ApiResponseView: View {
    let title: String?
    let value: String

    var body: some View {
        Text(title.map { "\($0): \(value)" } ?? value)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
