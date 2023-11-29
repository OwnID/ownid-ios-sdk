import SwiftUI
import Combine

extension OwnID.UISDK {
    public struct LegacyOTPTextFieldView: View {
        @ObservedObject var viewModel: OneTimePassword.ViewModel
        @State private var focusedField: Int?
        
        public var body: some View {
            HStack(spacing: 8) {
                ForEach(0..<viewModel.codeLength, id: \.self) { index in
                    ZStack {
                        Rectangle()
                            .foregroundColor(OwnID.Colors.otpTitleBackgroundColor)
                            .border(titleBorderColor(for: index))
                            .cornerRadius(cornerRadiusValue)
                            .overlay(
                                RoundedRectangle(cornerRadius: cornerRadiusValue)
                                    .stroke(titleBorderColor(for: index), lineWidth: 1)
                            )
                        FocusedTextField(text: $viewModel.codes[index], focusedField: $focusedField, equals: index, configuration: { textField in
                            textField.keyboardType = .numberPad
                            textField.textAlignment = .center
                            textField.tag = index
                            textField.textColor = UIColor(OwnID.Colors.blue)
                            textField.font = UIFont.systemFont(ofSize: 20, weight: .medium)
                        })
                        .onTapGesture(perform: {
                            focusedField = index
                        })
                            .disabled(viewModel.isDisabled)
                            .padding(8)
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 50, maxHeight: 50)
                }
            }
            .onChange(of: viewModel.currentFocusedFieldIndex, perform: { newValue in
                focusedField = newValue
            })
            .onChange(of: viewModel.codes, perform: { newValue in
                guard let index = focusedField else { return }
                viewModel.processTextChange(for: index, binding: $viewModel.codes[index])
            })
            .onAppear() {
                focusedField = 0
            }
        }
        
        private func titleBorderColor(for index: Int) -> Color {
            focusedField == index ? OwnID.Colors.otpTitleSelectedBorderColor : OwnID.Colors.otpTitleBorderColor
        }
    }
}
