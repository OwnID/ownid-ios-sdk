import SwiftUI
import UIKit

extension Character {
    var ownIDASCIIDecimalDigit: Character? {
        guard unicodeScalars.count == 1,
            let scalar = unicodeScalars.first,
            scalar.properties.numericType == .decimal,
            let value = wholeNumberValue,
            (0...9).contains(value)
        else {
            return nil
        }

        return Character(String(value))
    }
}

extension String {
    func ownIDNormalizedASCIIDigits(maximumLength: Int) -> String {
        String(compactMap(\.ownIDASCIIDecimalDigit).prefix(max(maximumLength, 1)))
    }
}

internal struct OTPEntryField: View {
    @Binding private var code: String
    private let codeLength: Int
    private let isEditable: Bool
    private let isErrorVisible: Bool
    private let isReadyForInitialFocus: Bool
    private let initialFocusResetID: String
    private let externalFocusRequestToken: Int
    private let colors: OwnIDColors
    private let accessibilityLabel: String
    private let accessibilityHint: String

    @State private var isKeyboardFocused = false
    @State private var focusRequestToken = -1
    @State private var isInitialFocusPending = true

    internal init(
        code: Binding<String>,
        codeLength: Int,
        isEditable: Bool,
        isErrorVisible: Bool,
        isReadyForInitialFocus: Bool,
        initialFocusResetID: String,
        externalFocusRequestToken: Int,
        colors: OwnIDColors,
        accessibilityLabel: String,
        accessibilityHint: String
    ) {
        self._code = code
        self.codeLength = max(codeLength, 1)
        self.isEditable = isEditable
        self.isErrorVisible = isErrorVisible
        self.isReadyForInitialFocus = isReadyForInitialFocus
        self.initialFocusResetID = initialFocusResetID
        self.externalFocusRequestToken = externalFocusRequestToken
        self.colors = colors
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
    }

    internal var body: some View {
        OTPTextInputBridge(
            text: $code,
            maximumLength: codeLength,
            isEditable: isEditable,
            focusRequestToken: focusRequestToken,
            onFocusChanged: { isFocused in
                isKeyboardFocused = isFocused
            }
        )
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .accessibilityLabelCompat(accessibilityLabel)
        .accessibilityHintCompat(accessibilityHint)
        .overlayCompat {
            OTPCodeSlots(
                code: code,
                codeLength: codeLength,
                isFocused: isKeyboardFocused,
                isErrorVisible: isErrorVisible,
                colors: colors,
                onTap: { requestFocus() }
            )
            .accessibilityHiddenCompat(true)
        }
        .onAppear {
            requestInitialFocusIfNeeded(ready: isReadyForInitialFocus)
        }
        .onChangeCompat(of: isReadyForInitialFocus) { ready in
            requestInitialFocusIfNeeded(ready: ready)
        }
        .onChangeCompat(of: initialFocusResetID) { _ in
            isInitialFocusPending = true
            requestInitialFocusIfNeeded(ready: isReadyForInitialFocus)
        }
        .onChangeCompat(of: isEditable) { _ in
            requestFocus()
        }
        .onChangeCompat(of: externalFocusRequestToken) { token in
            guard token > 0 else { return }
            requestFocus()
        }
    }

    @MainActor
    private func requestFocus() {
        isKeyboardFocused = true
        focusRequestToken &+= 1
    }

    @MainActor
    private func requestInitialFocusIfNeeded(ready: Bool) {
        guard isInitialFocusPending, ready else { return }
        isInitialFocusPending = false
        requestFocus()
    }
}

private struct OTPTextInputBridge: UIViewRepresentable {
    typealias UIViewType = UITextField

    @Binding private var text: String
    private let maximumLength: Int
    private let isEditable: Bool
    private let focusRequestToken: Int
    private let onFocusChanged: @MainActor (Bool) -> Void

    fileprivate init(
        text: Binding<String>,
        maximumLength: Int,
        isEditable: Bool,
        focusRequestToken: Int,
        onFocusChanged: @escaping @MainActor (Bool) -> Void
    ) {
        self._text = text
        self.maximumLength = max(maximumLength, 1)
        self.isEditable = isEditable
        self.focusRequestToken = focusRequestToken
        self.onFocusChanged = onFocusChanged
    }

    fileprivate func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.keyboardType = .numberPad
        textField.textContentType = .oneTimeCode
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.spellCheckingType = .no
        textField.textColor = .clear
        textField.tintColor = .clear
        textField.backgroundColor = .clear
        textField.isAccessibilityElement = true
        textField.accessibilityElementsHidden = false
        textField.delegate = context.coordinator
        textField.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        return textField
    }

    fileprivate func updateUIView(_ textField: UITextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.maximumLength = maximumLength
        context.coordinator.isEditable = isEditable
        context.coordinator.onFocusChanged = onFocusChanged

        if textField.text != text {
            textField.text = text
        }

        // Keep the field enabled so UIKit preserves first responder while a request is in flight.
        textField.isEnabled = true

        guard !context.environment.ownIDSuppressTextInputFocus else {
            context.coordinator.cancelPendingFocusRequest()
            if textField.isFirstResponder {
                textField.resignFirstResponder()
            }
            return
        }

        context.coordinator.requestFocusIfNeeded(token: focusRequestToken, for: textField)
    }

    fileprivate static func dismantleUIView(_ textField: UITextField, coordinator: Coordinator) {
        coordinator.cancelPendingFocusRequest()
        textField.resignFirstResponder()
        textField.delegate = nil
        textField.removeTarget(coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
    }

    fileprivate func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, maximumLength: maximumLength)
    }

    fileprivate final class Coordinator: NSObject, UITextFieldDelegate {
        fileprivate var text: Binding<String>
        fileprivate var maximumLength: Int
        fileprivate var isEditable = true
        fileprivate var onFocusChanged: @MainActor (Bool) -> Void = { _ in }

        private let focusCoordinator = TextFieldFocusCoordinator()

        fileprivate init(text: Binding<String>, maximumLength: Int) {
            self.text = text
            self.maximumLength = maximumLength
        }

        fileprivate func cancelPendingFocusRequest() {
            focusCoordinator.cancelPendingFocusRequests()
        }

        fileprivate func requestFocusIfNeeded(token: Int, for textField: UITextField) {
            focusCoordinator.requestFocus(token: token, for: textField)
        }

        fileprivate func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            guard isEditable else { return false }

            let currentText = textField.text ?? ""
            let nextText = (currentText as NSString).replacingCharacters(in: range, with: string)
            return nextText.ownIDNormalizedASCIIDigits(maximumLength: maximumLength).count <= maximumLength
        }

        fileprivate func textFieldDidBeginEditing(_ textField: UITextField) {
            onFocusChanged(true)
        }

        fileprivate func textFieldDidEndEditing(_ textField: UITextField) {
            onFocusChanged(false)
        }

        @objc
        fileprivate func editingChanged(_ sender: UITextField) {
            let nextText = normalize(sender.text ?? "")
            if sender.text != nextText {
                sender.text = nextText
            }
            if text.wrappedValue != nextText {
                text.wrappedValue = nextText
            }
        }

        private func normalize(_ text: String) -> String {
            text.ownIDNormalizedASCIIDigits(maximumLength: maximumLength)
        }
    }
}

private struct OTPCodeSlots: View {
    private static let fallbackWidth: CGFloat = 288
    private static let maxSlotSize: CGFloat = 50

    private let code: String
    private let codeLength: Int
    private let isFocused: Bool
    private let isErrorVisible: Bool
    private let colors: OwnIDColors
    private let onTap: @MainActor () -> Void

    @State private var availableWidth: CGFloat = 0

    fileprivate init(
        code: String,
        codeLength: Int,
        isFocused: Bool,
        isErrorVisible: Bool,
        colors: OwnIDColors,
        onTap: @escaping @MainActor () -> Void
    ) {
        self.code = code
        self.codeLength = max(codeLength, 1)
        self.isFocused = isFocused
        self.isErrorVisible = isErrorVisible
        self.colors = colors
        self.onTap = onTap
    }

    fileprivate var body: some View {
        let layout = Self.layout(width: availableWidth, codeLength: codeLength)
        let digits = code.map(String.init)

        HStack(spacing: layout.spacing) {
            ForEach(0..<codeLength, id: \.self) { index in
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(colors.fieldBackground)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(borderColor(for: index), lineWidth: 1.5)

                    Text(index < digits.count ? digits[index] : "")
                        .foregroundColor(colors.primary)
                        .font(digitFont)
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                }
                .frame(width: layout.slotSize, height: layout.slotSize)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(height: layout.slotSize)
        .background(widthReader)
        .environment(\.layoutDirection, .leftToRight)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var widthReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear {
                    updateAvailableWidth(proxy.size.width)
                }
                .onChangeCompat(of: proxy.size.width) { width in
                    updateAvailableWidth(width)
                }
        }
    }

    private var digitFont: Font {
        if #available(iOS 14.0, *) {
            return .system(.title2, design: .monospaced).weight(.medium)
        }
        return .system(.title, design: .monospaced).weight(.medium)
    }

    private func borderColor(for index: Int) -> Color {
        if isErrorVisible { return colors.error }
        if isFocused, code.count < codeLength, index == code.count { return colors.primary }
        return colors.onSurfaceVariant
    }

    private static func layout(width: CGFloat, codeLength: Int) -> (slotSize: CGFloat, spacing: CGFloat) {
        let codeLength = max(codeLength, 1)
        let spacing = slotSpacing(for: codeLength)
        let width = width > 0 ? width : fallbackWidth
        let availableSlotWidth = max(width - CGFloat(codeLength - 1) * spacing, 0) / CGFloat(codeLength)

        return (min(floor(availableSlotWidth), maxSlotSize), spacing)
    }

    private static func slotSpacing(for codeLength: Int) -> CGFloat {
        switch codeLength {
        case ...6: return 8
        case 7...8: return 6
        default: return 4
        }
    }

    @MainActor
    private func updateAvailableWidth(_ width: CGFloat) {
        guard abs(availableWidth - width) > 0.5 else { return }
        availableWidth = width
    }
}
