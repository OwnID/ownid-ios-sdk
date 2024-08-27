import Gigya
import WebKit

extension OwnID.GigyaSDK {
    class OwnIDGigyaWebBridge<T: GigyaAccountProtocol>: GigyaWebBridge<T> {
        let webBridge = OwnID.CoreSDK.createWebViewBridge()
        
        override func attachTo(webView: WKWebView, viewController: UIViewController, pluginEvent: @escaping (GigyaPluginEvent<T>) -> Void) {
            super.attachTo(webView: webView, viewController: viewController, pluginEvent: pluginEvent)
            
            webBridge.injectInto(webView: webView, allowedOriginRules: ["https://www.gigya.com"])
        }
    }
}
