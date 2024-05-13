import Foundation

extension OwnID.CoreSDK.CoreViewModel {
    struct State {
        var configuration: OwnID.CoreSDK.LocalConfiguration?

        var loginId: String
        let type: OwnID.CoreSDK.RequestType
        let loginType: OwnID.CoreSDK.LoginType?
        let supportedLanguages: OwnID.CoreSDK.Languages
        
        var browserViewModelStore: Store<OwnID.CoreSDK.BrowserOpenerViewModel.State, OwnID.CoreSDK.BrowserOpenerViewModel.Action>!
        var browserViewModel: OwnID.CoreSDK.BrowserOpenerViewModel?
        
        var authManagerStore: Store<OwnID.CoreSDK.AuthManager.State, OwnID.CoreSDK.AuthManager.Action>!
        var authManager: OwnID.CoreSDK.AuthManager?
        
        var oneTimePasswordStore: Store<OwnID.UISDK.OneTimePassword.ViewState, OwnID.UISDK.OneTimePassword.Action>!
        
        var idCollectViewStore: Store<OwnID.UISDK.IdCollect.ViewState, OwnID.UISDK.IdCollect.Action>!
        
        var shouldStartFlowOnConfigurationReceive = true
        var shouldIgnoreLoginIdOnInit = false
        
        var sessionVerifier: OwnID.CoreSDK.SessionVerifier!
        var session: OwnID.CoreSDK.SessionService!
        var stopUrl: URL!
        var finalUrl: URL!
        var context: OwnID.CoreSDK.Context!
        
        //TODO: temporary desicion until move auth manager methods to FidoAuthStep class")
        var fidoStep: FidoAuthStep!
        var otpStep: OTPAuthStep!
        var idCollectStep: IdCollectStep!
    }
}
