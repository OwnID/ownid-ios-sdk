import SwiftUI
import UIKit
import Combine

extension OwnID.UISDK {
    static func showOTPView(store: Store<OwnID.UISDK.OneTimePassword.ViewState, OwnID.UISDK.OneTimePassword.Action>,
                            loginId: String,
                            otpLength: Int,
                            restartUrl: URL,
                            type: OwnID.CoreSDK.CoreViewModel.Step.StepType,
                            verificationType: OwnID.CoreSDK.Verification.VerificationType,
                            context: OwnID.CoreSDK.Context?) {
        let operationType: OwnID.UISDK.OneTimePassword.OperationType = type == .loginIDAuthorization ? .oneTimePasswordSignIn : .verification
        let view = OwnID.UISDK.OneTimePassword.OneTimePasswordView(store: store,
                                                                   loginId: loginId,
                                                                   codeLength: otpLength,
                                                                   restartURL: restartUrl,
                                                                   operationType: operationType,
                                                                   verificationType: verificationType,
                                                                   context: context)
        view.presentAsPopup()
    }
}

extension OwnID.UISDK.OneTimePassword {
    enum OperationType: String {
        case verification = "verify"
        case oneTimePasswordSignIn = "sign"
        
        var metricName: String {
            switch self {
            case .verification:
                "OTP Code Verification"
            case .oneTimePasswordSignIn:
                "Fallback OTP Code"
            }
        }
    }
    
    struct OneTimePasswordView: Popup {
        static func == (lhs: OwnID.UISDK.OneTimePassword.OneTimePasswordView, rhs: OwnID.UISDK.OneTimePassword.OneTimePasswordView) -> Bool {
            lhs.uuid == rhs.uuid
        }
        
        private enum Constants {
            static let iPhoneSE1Height = 1136.0
            static let padding = UIScreen.main.nativeBounds.height == iPhoneSE1Height ? 8.0 : 26.0
            static let titleBottomPadding = UIScreen.main.nativeBounds.height == iPhoneSE1Height ? 10.0 : 16.0
            static let messageBottomPadding = UIScreen.main.nativeBounds.height == iPhoneSE1Height ? 10.0 : 20.0

            static let closeImageName = "closeImage"
            static let codeLengthReplacement = "%CODE_LENGTH%"
            static let emailReplacement = "%LOGIN_ID%"
        }
        
        private let uuid = UUID().uuidString
        
        private let viewModel: ViewModel
        @ObservedObject var store: Store<ViewState, Action>
        private let codeLength: Int
        private let operationType: OperationType
        private let restartURL: URL
        private let verificationType: OwnID.CoreSDK.Verification.VerificationType
        private let context: OwnID.CoreSDK.Context?

        @State private var emailSentText: String
        private let emailSentTextChangedClosure: (() -> String)
        @State private var isTranslationChanged = false
        
        private var cancel: String {
            OwnID.CoreSDK.TranslationsSDK.TranslationKey.stepsCancel.localized()
        }
        
        init(store: Store<ViewState, Action>,
             loginId: String,
             codeLength: Int,
             restartURL: URL,
             operationType: OperationType = .oneTimePasswordSignIn,
             verificationType: OwnID.CoreSDK.Verification.VerificationType,
             context: OwnID.CoreSDK.Context?) {
            self.store = store
            self.codeLength = codeLength
            self.restartURL = restartURL
            self.viewModel = ViewModel(codeLength: codeLength, store: store, context: context, operationType: operationType, loginId: loginId)
            self.verificationType = verificationType
            self.operationType = operationType
            self.context = context
            
            let emailSentTextChangedClosure = {
                var text = OwnID.CoreSDK.TranslationsSDK.TranslationKey.otpMessage(operationType: operationType.rawValue,
                                                                                   verificationType: verificationType.rawValue).localized()
                let codeLengthReplacement = Constants.codeLengthReplacement
                let emailReplacement = Constants.emailReplacement
                text = text.replacingOccurrences(of: codeLengthReplacement, with: String(codeLength))
                text = text.replacingOccurrences(of: emailReplacement, with: loginId)
                return text
            }
            self.emailSentTextChangedClosure = emailSentTextChangedClosure
            _emailSentText = State(initialValue: emailSentTextChangedClosure())
        }
        
        @ViewBuilder
        private func resendView() -> some View {
            if store.value.isDisplayingDidNotGetCode && !store.value.isLoading && store.value.error == nil {
                Button {
                    store.send(.resendCode(operationType: operationType))
                } label: {
                    Text(localizedKey: .otpResend(operationType: operationType.rawValue, verificationType: verificationType.rawValue))
                        .font(.system(size: 14))
                        .bold()
                        .foregroundColor(OwnID.Colors.blue)
                }
            }
        }
        
        private func notYouView() -> some View {
            ZStack {
                Button {
                    store.send(.emailIsNotRecieved(operationType: operationType, flowFinished: store.value.isFlowFinished))
                } label: {
                    Text(localizedKey: .otpNotYou(operationType: operationType.rawValue, verificationType: verificationType.rawValue))
                        .font(.system(size: 14))
                        .bold()
                        .foregroundColor(OwnID.Colors.blue)
                }
            }
            .frame(height: 28)
        }
        
        @ViewBuilder
        private func errorView() -> some View {
            if let error = store.value.error, error.isGeneralError {
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
            if let error = store.value.error, !error.isGeneralError {
                HStack {
                    Text(error.userMessage)
                        .font(.system(size: 12))
                        .multilineTextAlignment(.leading)
                        .foregroundColor(OwnID.Colors.errorColor)
                }
            }
        }
        
        private func closeButton() -> some View {
            Button {
                dismiss()
            } label: {
                Image(Constants.closeImageName, bundle: .resourceBundle)
            }
            .modifier(AccessibilityLabelModifier(accessibilityLabel: cancel))
            .padding(.trailing, 10)
            .padding(.top, 12)
        }
        
        private func otpTextFieldView() -> some View {
            if #available(iOS 15.0, *) {
                return OwnID.UISDK.OTPTextFieldView(viewModel: viewModel)
                    .environment(\.layoutDirection, .leftToRight)
            } else {
                return  OwnID.UISDK.LegacyOTPTextFieldView(viewModel: viewModel)
            }
        }
        
        func createContent() -> some View {
            Group {
                VStack {
                    topSection()
                    otpTextFieldView()
                        .shake(animatableData: store.value.attempts)
                        .onChange(of: store.value.attempts) { newValue in
                            viewModel.resetCode()
                        }
                        .onChange(of: store.value.error) { newValue in
                            if newValue != nil {
                                viewModel.disableCodes()
                            }
                        }
                    ZStack {
                        if store.value.isLoading {
                            OwnID.UISDK.SpinnerLoaderView(spinnerColor: OwnID.Colors.spinnerColor,
                                                          circleColor: OwnID.Colors.spinnerBackgroundColor,
                                                          viewBackgroundColor: .clear,
                                                          isLoading: .constant(true))
                            .frame(width: 28, height: 28)
                        }
                        resendView()
                        errorText()
                    }
                    .frame(height: 32)
                    notYouView()
                        .padding([.top, .bottom], 8)
                    errorView()
                }
                .frame(minWidth: 0, maxWidth: .infinity)
                .padding(.all, Constants.padding)
                .modifier(Overlay(view: closeButton(), alignment: .topTrailing))
                .onReceive(OwnID.CoreSDK.shared.translationsModule.translationsChangePublisher) {
                    emailSentText = emailSentTextChangedClosure()
                    isTranslationChanged.toggle()
                }
            }
            .environment(\.layoutDirection, OwnID.CoreSDK.shared.translationsModule.isRTLLanguage ? .rightToLeft : .leftToRight)
        }
        
        func backgroundOverlayTapped() {
            dismiss()
        }
        
        private func dismiss() {
            OwnID.UISDK.PopupManager.dismissPopup()
            store.send(.cancel(operationType: operationType))
        }
        
        @ViewBuilder
        private func emptyTranslationView() -> some View {
            if isTranslationChanged {
                EmptyView()
            }
        }
        
        private func topSection() -> some View {
            VStack {
                Text(localizedKey: .otpTitle(operationType: operationType.rawValue, verificationType: verificationType.rawValue))
                    .font(.system(size: 20))
                    .bold()
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .padding(.bottom, Constants.titleBottomPadding)
                Text(verbatim: emailSentText)
                    .multilineTextAlignment(.center)
                    .foregroundColor(OwnID.Colors.popupContentMessageColor)
                    .font(.system(size: 16))
                    .padding(.bottom, Constants.messageBottomPadding)
                Text(localizedKey: .otpDescription(operationType: operationType.rawValue, verificationType: verificationType.rawValue))
                    .font(.system(size: 16))
                    .padding(.bottom, 12)
            }
            .modifier(Overlay(view: emptyTranslationView()))
        }
    }
}
