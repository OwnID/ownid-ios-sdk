import SwiftUI

extension OwnID.UISDK {
    static func showEnrollView(store: Store<OwnID.UISDK.Enroll.ViewState, OwnID.UISDK.Enroll.Action>, loginId: String, sourceMetricName: String) {
        let view = OwnID.UISDK.Enroll.EnrollView(store: store, loginId: loginId, sourceMetricName: sourceMetricName)
        view.presentAsPopup()
    }
}

extension OwnID.UISDK {
    enum Enroll { }
}

extension OwnID.UISDK.Enroll {
    struct EnrollView: Popup {
        private enum Constants {
            static let closeImageName = "closeImage"
            static let faceImageName = "faceidImage"
        }
        
        @ObservedObject var store: Store<ViewState, Action>
        @ObservedObject private var viewModel: ViewModel
        private var loginId: String
        
        @State private var isTranslationChanged = false
        
        private var cancel: String {
            OwnID.CoreSDK.TranslationsSDK.TranslationKey.stepsCancel.localized()
        }
        
        init(store: Store<ViewState, Action>, loginId: String, sourceMetricName: String) {
            self.store = store
            self.loginId = loginId
            self.viewModel = ViewModel(store: store, loginId: loginId, sourceMetricName: sourceMetricName)
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
        
        
        func backgroundOverlayTapped() {
            dismiss()
        }
        
        @ViewBuilder
        private func emptyTranslationView() -> some View {
            if isTranslationChanged {
                EmptyView()
            }
        }
        
        func createContent() -> some View {
            Group {
                viewContent()
                    .onReceive(OwnID.CoreSDK.shared.translationsModule.translationsChangePublisher) {
                        isTranslationChanged.toggle()
                    }
                    .modifier(Overlay(view: emptyTranslationView()))
                    .modifier(Overlay(view: closeButton(), alignment: .topTrailing))
            }
            .environment(\.layoutDirection, OwnID.CoreSDK.shared.translationsModule.isRTLLanguage ? .rightToLeft : .leftToRight)
        }
        
        private func viewContent() -> some View {
            VStack {
                Text(localizedKey: .enrollTitle)
                    .font(.system(size: 20))
                    .bold()
                    .multilineTextAlignment(.center)
                    .padding(.top, 20)
                    .padding(.bottom, 8)
                Text(localizedKey: .enrollDescription)
                    .font(.system(size: 14))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 30)
                continueButton()
                notNowButton()
            }
            .padding(.all, 20)
            .frame(maxWidth: .infinity)
        }
        
        private func continueButton() -> some View {
            Button {
                viewModel.continueFlow()
            } label: {
                ZStack {
                    HStack {
                        Image(Constants.faceImageName, bundle: .resourceBundle)
                            .renderingMode(.template)
                            .foregroundColor(.white)
                        Text(localizedKey: .enrollContinue)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .opacity(viewModel.isLoading ? 0 : 1)
                    OwnID.UISDK.SpinnerLoaderView(spinnerColor: OwnID.Colors.spinnerColor,
                                                  circleColor: OwnID.Colors.spinnerBackgroundColor,
                                                  viewBackgroundColor: OwnID.Colors.blue,
                                                  isLoading: $viewModel.isLoading)
                    .frame(width: 24, height: 24)
                    .opacity(viewModel.isLoading ? 1 : 0)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 4)
            }
            .frame(height: 44)
            .background(backgroundRectangle(color: OwnID.Colors.blue))
            .padding(.bottom, 20)
        }
        
        private func notNowButton() -> some View {
            Button {
                viewModel.handleNotNow()
            } label: {
                Text(localizedKey: .enrollSkip)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(OwnID.Colors.blue)
            }
            .padding(.bottom, 10)
        }
        
        private func dismiss() {
            viewModel.dismiss()
            OwnID.UISDK.PopupManager.dismissPopup()
        }
    }
}

