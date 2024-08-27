import Foundation
import Combine

extension OwnID.CoreSDK.CoreViewModel {
    class WebAppStep: BaseStep {
        private let step: Step
        
        init(step: Step) {
            self.step = step
        }
        
        override func run(state: inout OwnID.CoreSDK.CoreViewModel.State) -> [Effect<OwnID.CoreSDK.CoreViewModel.Action>] {
            guard let urlString = step.webAppData?.url else {
                let message = OwnID.CoreSDK.ErrorMessage.dataIsMissingError(dataInfo: "url")
                return errorEffect(.userError(errorModel: OwnID.CoreSDK.UserErrorModel(message: message)), type: Self.self)
            }
            
            guard let loginIdSettings = state.configuration?.loginIdSettings else {
                let message = OwnID.CoreSDK.ErrorMessage.noLocalConfig
                return errorEffect(.userError(errorModel: OwnID.CoreSDK.UserErrorModel(message: message)), type: Self.self)
            }
            
            let viewModel = createBrowserVM(for: state.context,
                                            browserURL: urlString,
                                            loginId: OwnID.CoreSDK.LoginId(value: state.loginId, settings: loginIdSettings),
                                            store: state.browserViewModelStore,
                                            redirectionURLString: state.configuration?.redirectionURL)
            state.browserViewModel = viewModel
            return []
        }
        
        private func createBrowserVM(for context: String,
                                     browserURL: String,
                                     loginId: OwnID.CoreSDK.LoginId?,
                                     store: Store<OwnID.CoreSDK.BrowserOpenerViewModel.State, OwnID.CoreSDK.BrowserOpenerViewModel.Action>,
                                     redirectionURLString: OwnID.CoreSDK.RedirectionURLString?) -> OwnID.CoreSDK.BrowserOpenerViewModel {
            let redirectionEncoded = (redirectionURLString ?? "").addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
            let redirect = redirectionEncoded! + "?context=" + context
            let redirectParameter = "&redirectURI=" + redirect
            var urlString = browserURL
            if let loginId, loginId.settings.type == .email {
                var emailSet = CharacterSet.urlHostAllowed
                emailSet.remove("+")
                if let encoded = loginId.value.addingPercentEncoding(withAllowedCharacters: emailSet) {
                    let emailParameter = "&e=" + encoded
                    urlString.append(emailParameter)
                }
            }
            urlString.append(redirectParameter)
            let url = URL(string: urlString)!
            let vm = OwnID.CoreSDK.BrowserOpenerViewModel(store: store, url: url, redirectionURL: redirectionURLString ?? "")
            return vm
        }
    }
}
