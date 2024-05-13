
import SwiftUI
import Combine

extension OwnID.UISDK.IdCollect {
    struct LegacyIdCollectView: Popup {
        private enum Constants {
            static let phoneCodeArrow = "phoneCodeArrow"
            static let closeImageName = "closeImage"
        }
        
        enum FocusField: Hashable {
            case loginId
        }
        
        public static func == (lhs: OwnID.UISDK.IdCollect.LegacyIdCollectView,
                               rhs: OwnID.UISDK.IdCollect.LegacyIdCollectView) -> Bool {
            lhs.uuid == rhs.uuid
        }
        private let uuid = UUID().uuidString
        private let loginIdPublisher = PassthroughSubject<String, Never>()
        private let phoneDialCodePublisher = PassthroughSubject<String, Never>()
        
        private let closeClosure: () -> Void
        
        @ObservedObject var store: Store<ViewState, Action>
        @ObservedObject private var viewModel: ViewModel
        @State private var focusedField: FocusField?
        @State private var loginId = ""
        @State var presentList = false
        @State var selectedPhoneCode: OwnID.CoreSDK.PhoneCode?
        private let loginIdSettings: OwnID.CoreSDK.LoginIdSettings
        private let phoneCodes: [OwnID.CoreSDK.PhoneCode]

        private var bag = Set<AnyCancellable>()
        
        @State private var isTranslationChanged = false
        
        private var placeholder: String {
            OwnID.CoreSDK.TranslationsSDK.TranslationKey.idCollectPlaceholder(type: viewModel.loginIdType.rawValue).localized()
        }
        
        private var cancel: String {
            OwnID.CoreSDK.TranslationsSDK.TranslationKey.stepsCancel.localized()
        }
        
        private var phoneCodeEmoji: String {
            selectedPhoneCode?.emoji ?? viewModel.defaultPhoneCode?.emoji ?? ""
        }
        
        private var phoneCodeDial: String {
            selectedPhoneCode?.dialCode ?? viewModel.defaultPhoneCode?.dialCode ?? ""
        }
        
        init(store: Store<ViewState, Action>,
             loginId: String,
             loginIdSettings: OwnID.CoreSDK.LoginIdSettings,
             phoneCodes: [OwnID.CoreSDK.PhoneCode],
             closeClosure: @escaping () -> Void) {
            self.store = store
            self.loginId = loginId
            self.loginIdSettings = loginIdSettings
            self.phoneCodes = phoneCodes
            self.closeClosure = closeClosure
            self.viewModel = ViewModel(store: store, loginId: loginId, loginIdSettings: loginIdSettings, phoneCodes: phoneCodes)
            
            viewModel.updateLoginIdPublisher(loginIdPublisher.eraseToAnyPublisher())
            viewModel.updatePhoneDialCodePublisher(phoneDialCodePublisher.eraseToAnyPublisher())
        }
        
        private func closeButton() -> some View {
            Button {
                dismiss()
            } label: {
                Image(Constants.closeImageName, bundle: .resourceBundle)
            }
            .modifier(AccessibilityLabelModifier(accessibilityLabel: cancel))
            .padding(.trailing, 10.0)
            .padding(.top, 12.0)
        }
        
        @ViewBuilder
        private func emptyTranslationView() -> some View {
            if isTranslationChanged {
                EmptyView()
            }
        }
        
        public func createContent() -> some View {
            Group {
                viewContent()
                    .onChange(of: loginId) { newValue in loginIdPublisher.send(newValue) }
                    .onChange(of: selectedPhoneCode) { newValue in phoneDialCodePublisher.send(newValue?.dialCode ?? "") }
                    .onReceive(OwnID.CoreSDK.shared.translationsModule.translationsChangePublisher) {
                        isTranslationChanged.toggle()
                    }
                    .modifier(Overlay(view: emptyTranslationView()))
                    .modifier(Overlay(view: closeButton(), alignment: .topTrailing))
            }
            .environment(\.layoutDirection, OwnID.CoreSDK.shared.translationsModule.isRTLLanguage ? .rightToLeft : .leftToRight)
        }
        
        public func backgroundOverlayTapped() {
            dismiss()
        }
        
        private func dismiss() {
            store.send(.cancel)
            closeClosure()
        }
        
        @ViewBuilder
        private func topSection() -> some View {
            HStack {
                Text(localizedKey: viewModel.titleKey)
                    .font(.system(size: 20))
                    .bold()
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 10.0)
            .padding(.horizontal, 26.0)
            .padding(.bottom, 8.0)
        }
        
        @ViewBuilder
        private func errorView() -> some View {
            if store.value.error != nil {
                Text(localizedKey: .stepsError)
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .foregroundColor(.white)
                    .background(RoundedRectangle(cornerRadius: 4))
            }
        }
        
        @ViewBuilder
        private func errorText() -> some View {
            if viewModel.isError {
                HStack {
                    Text(localizedKey: .idCollectError(type: viewModel.loginIdType.rawValue))
                        .multilineTextAlignment(.center)
                        .foregroundColor(OwnID.Colors.errorColor)
                        .padding(.bottom, 8.0)
                }
            }
        }
        
        @ViewBuilder
        private func continueButton() -> some View {
            if !store.value.isFlowFinished {
                OwnID.UISDK.AuthButton(visualConfig: OwnID.UISDK.VisualLookConfig(),
                                       actionHandler: { viewModel.postLoginId() },
                                       isLoading: $viewModel.isLoading,
                                       buttonState: $viewModel.buttonState,
                                       translationKey: .idCollectContinue(type: viewModel.loginIdType.rawValue))
            }
        }
        
        @ViewBuilder
        private func loginIdTextField() -> some View {
            let loginIdType = loginIdSettings.type

            if loginIdType == .email {
                mainTextField()
            } else if loginIdType == .phoneNumber {
                HStack {
                    countryCodeView()
                    mainTextField()
                }
            }
        }
        
        private func countryCodeView() -> some View {
            HStack {
                Text(phoneCodeEmoji)
                Text(phoneCodeDial)
                    .minimumScaleFactor(0.5)
                Spacer()
                Image(Constants.phoneCodeArrow, bundle: .resourceBundle)
            }
            .font(.system(size: 16))
            .padding(11)
            .frame(width: 100, height: 40)
            .background(Rectangle().fill(OwnID.Colors.idCollectViewLoginFieldBackgroundColor))
            .cornerRadius(cornerRadiusValue)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadiusValue)
                    .stroke(borderColor, lineWidth: 1)
            )
            .padding(.top, 12)
            .foregroundColor(.primary)
            .onTapGesture {
                presentList = true
            }
            .sheet(isPresented: $presentList) {
                List(viewModel.phoneCodes) { code in
                    HStack {
                        Text(code.emoji)
                        Text(code.name)
                        Spacer()
                        Text(code.dialCode)
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        presentList = false
                        selectedPhoneCode = code
                    }
                }
                .modifier(PresentationDetents())
            }
        }
        
        private func mainTextField() -> some View {
            FocusedTextField(text: $loginId, focusedField: $focusedField, equals: .loginId, configuration: { textField in
                textField.placeholder = placeholder
                textField.keyboardType = loginIdSettings.type == .email ? .emailAddress : .numberPad
                textField.autocapitalizationType = .none
                textField.autocorrectionType = .no
                textField.font = UIFont.systemFont(ofSize: 16)
            })
            .frame(height: 22)
            .onChange(of: loginId) { _ in
                viewModel.isError = false
            }
            .padding(10.0)
            .background(Rectangle().fill(OwnID.Colors.idCollectViewLoginFieldBackgroundColor))
            .cornerRadius(cornerRadiusValue)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadiusValue)
                    .stroke(borderColor, lineWidth: 1)
            )
            .padding(.top, 20.0)
            .padding(.bottom, 8.0)
        }
        
        @ViewBuilder
        private func viewContent() -> some View {
            VStack {
                topSection()
                VStack {
                    Text(localizedKey: viewModel.messageKey)
                        .font(.system(size: 16))
                        .foregroundColor(OwnID.Colors.popupContentMessageColor)
                        .padding(.bottom, 8.0)
                    errorText()
                    loginIdTextField()
                    continueButton()
                        .padding(.bottom, 8.0)
                    errorView()
                }
            }
            .padding(.all, 22.0)
            .onAppear() {
                focusedField = .loginId
            }
        }
        
        var borderColor: Color {
            if focusedField == .loginId {
                return OwnID.Colors.blue
            } else {
                return OwnID.Colors.idCollectViewLoginFieldBorderColor
            }
        }
    }
}

