import OwnIDCore
import SwiftUI
import UIKit

internal struct LoginIDCollectUIDefaultProvider: LoginIDCollectUIProvider, Sendable {
    @MainActor
    internal func content(
        uiState: LoginIDCollectUIState,
        uiStrings: LoginIDCollectStrings,
        errorTextProvider: ((ErrorCode) -> String)?,
        isReadyForInitialFocus: Bool
    ) -> AnyView {
        AnyView(
            LoginIDCollectDefaultView(
                uiState: uiState,
                uiStrings: uiStrings,
                errorTextProvider: errorTextProvider,
                isReadyForInitialFocus: isReadyForInitialFocus
            )
        )
    }
}

internal struct LoginIDCollectDefaultView: View {
    private let uiState: LoginIDCollectUIState
    private let uiStrings: LoginIDCollectStrings
    private let errorTextProvider: ((ErrorCode) -> String)?
    private let isReadyForInitialFocus: Bool
    @State private var isLoginIDFocused = false
    @State private var focusRequestID: Int = -1
    @State private var initialFocusPending = true
    @State private var continueThrottler = UserActionThrottler()
    @State private var errorFocusTrigger = 0

    @Environment(\.ownIDTheme) private var ownIDTheme
    @Environment(\.colorScheme) private var colorScheme

    internal init(
        uiState: LoginIDCollectUIState,
        uiStrings: LoginIDCollectStrings,
        errorTextProvider: ((ErrorCode) -> String)? = nil,
        isReadyForInitialFocus: Bool = true
    ) {
        self.uiState = uiState
        self.uiStrings = uiStrings
        self.errorTextProvider = errorTextProvider
        self.isReadyForInitialFocus = isReadyForInitialFocus
    }

    private var colors: OwnIDColors {
        (ownIDTheme ?? OwnIDTheme.capture(colorScheme: colorScheme)).colors
    }

    private var loginIDBinding: Binding<String> {
        Binding(
            get: { uiState.loginIDValue },
            set: { newValue in uiState.onLoginIDChange(newValue) }
        )
    }

    internal var body: some View {
        VStack(spacing: 4) {
            Text(uiStrings.title)
                .font(.system(.headline, design: .default).weight(.bold))
                .foregroundColor(colors.onSurface)
                .multilineTextAlignment(.center)
                .padding(EdgeInsets(top: 32, leading: 52, bottom: 8, trailing: 52))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)

            VStack {
                Text(uiStrings.message)
                    .font(.body)
                    .foregroundColor(colors.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                loginIDField

                errorMessageView

                HStack {
                    OwnIDTextButtonView(text: uiStrings.cancel, action: handleCancelTapped)
                    Spacer(minLength: 16)
                    OwnIDButtonView(text: uiStrings.cta, action: handleContinueTapped)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .onAppear { requestInitialLoginIDFocusIfNeeded(ready: isReadyForInitialFocus) }
        .onChangeCompat(of: isReadyForInitialFocus) { ready in
            requestInitialLoginIDFocusIfNeeded(ready: ready)
        }
        .onChangeCompat(of: uiState.error) { error in
            guard let error else { return }
            requestErrorAccessibilityFocus(message: errorText(for: error))
        }
    }

    private var textContentType: UITextContentType? {
        guard uiState.collectableLoginIDTypes.count == 1 else { return nil }
        switch uiState.collectableLoginIDTypes[0] {
        case .email: return .emailAddress
        case .phoneNumber: return .telephoneNumber
        case .userName: return .username
        default: return nil
        }
    }

    private var keyboardType: UIKeyboardType {
        guard uiState.collectableLoginIDTypes.count == 1 else { return .default }
        switch uiState.collectableLoginIDTypes[0] {
        case .email: return .emailAddress
        case .phoneNumber: return .phonePad
        default: return .default
        }
    }

    @MainActor
    private func handleCancelTapped() {
        uiState.onCancel()
    }

    @MainActor
    private func handleContinueTapped() {
        continueThrottler.processAction {
            if let error = uiState.error {
                requestErrorAccessibilityFocus(message: errorText(for: error))
            }
            uiState.onContinue()
        }
    }

    @ViewBuilder
    private var loginIDField: some View {
        LoginIDCollectTextField(
            text: loginIDBinding,
            isFocused: $isLoginIDFocused,
            placeholder: uiStrings.placeholder,
            textContentType: textContentType,
            keyboardType: keyboardType,
            focusRequestID: focusRequestID,
            colors: colors,
            accessibilityHint: uiState.error.map { errorText(for: $0) },
            onSubmit: handleContinueTapped
        )
        .fixedSize(horizontal: false, vertical: true)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6.0, style: .continuous).fill(colors.fieldBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 6.0, style: .continuous)
                .strokeBorder(isLoginIDFocused ? colors.primary : colors.onSurfaceVariant.opacity(0.5), lineWidth: 1)
        )
        .padding(.top, 4)
    }

    private var errorMessageView: some View {
        ZStack(alignment: .leading) {
            Text(" ")
                .font(.footnote)
                .hidden()

            if uiState.error != nil {
                if #available(iOS 15.0, *) {
                    AccessibilityFocusedErrorText(
                        message: errorText,
                        color: colors.error,
                        alignment: .leading,
                        focusTrigger: errorFocusTrigger
                    )
                } else {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundColor(colors.error)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .accessibilityHiddenCompat(uiState.error == nil)
    }

    @MainActor
    private func requestInitialLoginIDFocusIfNeeded(ready: Bool) {
        guard initialFocusPending else { return }
        guard ready else { return }
        initialFocusPending = false
        isLoginIDFocused = true
        focusRequestID &+= 1
    }

    @MainActor
    private func requestErrorAccessibilityFocus(message: String) {
        if #available(iOS 15.0, *) {
            errorFocusTrigger &+= 1
        } else {
            UIAccessibility.post(notification: .announcement, argument: message)
        }
    }
}

private struct LoginIDCollectTextField: UIViewRepresentable {
    fileprivate typealias UIViewType = UITextField

    @Binding fileprivate var text: String
    @Binding fileprivate var isFocused: Bool
    fileprivate let placeholder: String
    fileprivate let textContentType: UITextContentType?
    fileprivate let keyboardType: UIKeyboardType
    fileprivate let focusRequestID: Int
    fileprivate let colors: OwnIDColors
    fileprivate let accessibilityHint: String?
    fileprivate let onSubmit: @MainActor () -> Void

    fileprivate func makeUIView(context: UIViewRepresentableContext<LoginIDCollectTextField>) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.delegate = context.coordinator
        textField.font = .preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        textField.returnKeyType = .continue
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.spellCheckingType = .no
        textField.semanticContentAttribute = .forceLeftToRight
        textField.textAlignment = .left
        textField.setContentHuggingPriority(.required, for: .vertical)
        textField.setContentCompressionResistancePriority(.required, for: .vertical)
        textField.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        return textField
    }

    fileprivate func updateUIView(_ textField: UITextField, context: UIViewRepresentableContext<LoginIDCollectTextField>) {
        context.coordinator.text = $text
        context.coordinator.isFocused = $isFocused
        context.coordinator.onSubmit = onSubmit

        if #available(iOS 14.0, *) {
            textField.textColor = UIColor(colors.onSurface)
            textField.tintColor = UIColor(colors.primary)
            textField.attributedPlaceholder = NSAttributedString(
                string: placeholder,
                attributes: [.foregroundColor: UIColor(colors.onSurfaceVariant)]
            )
        } else {
            textField.textColor = .label
            textField.attributedPlaceholder = NSAttributedString(
                string: placeholder,
                attributes: [.foregroundColor: UIColor.secondaryLabel]
            )
        }
        textField.keyboardType = keyboardType
        textField.textContentType = textContentType
        textField.accessibilityLabel = placeholder
        textField.accessibilityHint = accessibilityHint
        textField.semanticContentAttribute = .forceLeftToRight
        textField.textAlignment = .left
        if textField.text != text {
            textField.text = text
        }

        guard !context.environment.ownIDSuppressTextInputFocus else {
            context.coordinator.cancelPendingFocusRequests()
            if textField.isFirstResponder {
                textField.resignFirstResponder()
            }
            return
        }

        if !isFocused, textField.isFirstResponder {
            textField.resignFirstResponder()
        }

        if context.coordinator.fulfilledFocusRequestToken != focusRequestID {
            context.coordinator.requestFocus(token: focusRequestID, for: textField)
        }
    }

    fileprivate static func dismantleUIView(_ textField: UITextField, coordinator: Coordinator) {
        coordinator.cancelPendingFocusRequests()
        textField.resignFirstResponder()
        textField.delegate = nil
        textField.removeTarget(coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
    }

    fileprivate func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused, onSubmit: onSubmit)
    }

    @MainActor
    fileprivate final class Coordinator: NSObject, UITextFieldDelegate {
        fileprivate var text: Binding<String>
        fileprivate var isFocused: Binding<Bool>
        fileprivate var onSubmit: @MainActor () -> Void
        private let focusCoordinator = TextFieldFocusCoordinator()

        fileprivate init(text: Binding<String>, isFocused: Binding<Bool>, onSubmit: @escaping @MainActor () -> Void) {
            self.text = text
            self.isFocused = isFocused
            self.onSubmit = onSubmit
        }

        fileprivate func cancelPendingFocusRequests() {
            focusCoordinator.cancelPendingFocusRequests()
        }

        fileprivate func requestFocus(token: Int, for textField: UITextField) {
            focusCoordinator.requestFocus(token: token, for: textField)
        }

        fileprivate var fulfilledFocusRequestToken: Int {
            focusCoordinator.fulfilledFocusRequestToken
        }

        @objc
        fileprivate func editingChanged(_ sender: UITextField) {
            let next = sender.text ?? ""
            if text.wrappedValue != next {
                text.wrappedValue = next
            }
        }

        fileprivate func textFieldDidBeginEditing(_ textField: UITextField) {
            if !isFocused.wrappedValue {
                Task { @MainActor in
                    if !self.isFocused.wrappedValue {
                        self.isFocused.wrappedValue = true
                    }
                }
            }
        }

        fileprivate func textFieldDidEndEditing(_ textField: UITextField) {
            if isFocused.wrappedValue {
                Task { @MainActor in
                    if self.isFocused.wrappedValue {
                        self.isFocused.wrappedValue = false
                    }
                }
            }
        }

        fileprivate func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            Task { @MainActor in
                onSubmit()
            }
            return false
        }
    }
}

extension LoginIDCollectDefaultView {
    fileprivate var errorText: String {
        guard let error = uiState.error else { return "" }
        return errorText(for: error)
    }

    fileprivate func errorText(for error: UIError) -> String {
        if error.errorCode == .loginIDValidationFailed { return uiStrings.error }
        return errorTextProvider?(error.errorCode) ?? error.localizedMessage
    }
}
