import Combine
import SwiftUI

extension OwnID.UISDK.IdCollect {
    final class ViewModel: ObservableObject {
        private enum Constants {
            static let defaultPhoneCode = "US"
        }
        
        private(set) var loginId = ""
        private(set) var phoneDialCode = ""
        
        @Published var isLoading = false
        @Published var buttonState: OwnID.UISDK.ButtonState = .enabled
        @Published var isError = false
        private let store: Store<ViewState, Action>
        private let loginIdSettings: OwnID.CoreSDK.LoginIdSettings
        private let isPasskeysSupported: Bool
        let phoneCodes: [OwnID.CoreSDK.PhoneCode]
        
        private var storeCancellable: AnyCancellable?
        private var bag = Set<AnyCancellable>()
        
        var titleKey: OwnID.CoreSDK.TranslationsSDK.TranslationKey {
            isPasskeysSupported ? .idCollectTitle(type: loginIdType.rawValue) : .idCollectNoBiometricsTitle(type: loginIdType.rawValue)
        }
        
        var messageKey: OwnID.CoreSDK.TranslationsSDK.TranslationKey {
            let type = loginIdType.rawValue
            return isPasskeysSupported ? .idCollectMessage(type: type) : .idCollectNoBiometricsMessage(type: type)
        }
        
        var loginIdType: OwnID.CoreSDK.LoginIdSettings.LoginIdType {
            return loginIdSettings.type
        }
        
        var defaultPhoneCode: OwnID.CoreSDK.PhoneCode? {
            if let code = phoneCodes.first(where: { $0.code == Constants.defaultPhoneCode }) {
                return code
            } else {
                return phoneCodes.first
            }
        }
        
        init(store: Store<ViewState, Action>,
             loginId: String,
             loginIdSettings: OwnID.CoreSDK.LoginIdSettings,
             isPasskeysSupported: Bool = OwnID.CoreSDK.isPasskeysSupported,
             phoneCodes: [OwnID.CoreSDK.PhoneCode]) {
            self.store = store
            self.loginId = loginId
            self.loginIdSettings = loginIdSettings
            self.isPasskeysSupported = isPasskeysSupported
            self.phoneCodes = phoneCodes
            
            storeCancellable = store.$value
                .map { $0.isLoading }
                .sink { [weak self] isLoading in
                    self?.isLoading = isLoading
                }
            
            store.send(.viewLoaded)
            
            phoneDialCode = defaultPhoneCode?.dialCode ?? ""
        }
        
        func updateLoginIdPublisher(_ loginIdPublisher: OwnID.CoreSDK.LoginIdPublisher) {
            loginIdPublisher.assign(to: \.loginId, on: self).store(in: &bag)
        }
        
        func updatePhoneDialCodePublisher(_ phoneDialCodePublisher: OwnID.CoreSDK.LoginIdPublisher) {
            phoneDialCodePublisher.assign(to: \.phoneDialCode, on: self).store(in: &bag)
        }
        
        func postLoginId() {
            let value: String
            
            switch loginIdSettings.type {
            case .phoneNumber:
                value = "\(phoneDialCode)\(loginId)"
            default:
                value = loginId
            }
            
            let loginIdObject = OwnID.CoreSDK.LoginId(value: value, settings: loginIdSettings)

            if loginIdObject.value.isEmpty || loginId.isEmpty || !loginIdObject.isValid {
                isError = true
                return
            }

            store.send(.loginIdEntered(loginId: loginIdObject.value))
        }
    }
}
