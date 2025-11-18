import SwiftUI
import WebKit

struct OwnIDFlowWebView: UIViewRepresentable {
    private enum Constants {
        static let defaultHtml = """
               <!DOCTYPE html>
               <html lang="en">
               <head>
                 <meta charset="UTF-8">
                 <title></title>
                 <link id="webapp-icon" rel="icon" type="image/png" href="https://cdn.prod.website-files.com/63e207687d9e033189f3c3f1/643fe358bb66c2a656709593_OwnID%20icon.png">
                 <meta name="viewport" content="width=device-width, initial-scale=1.0">
                 <style>
                  .spinner {--ownid-spinner-overlay-bg-color: #fff;--ownid-spinner-bg-color: rgba(133, 133, 133, .3);--ownid-spinner-bg-opasity: 1;--ownid-spinner-color: #858585;--ownid-spinner-size: 40px;position: absolute;z-index: 1;width: 100%;height: 100%;background-color: var(--ownid-spinner-overlay-bg-color);top: 0;left: 0;display: flex;justify-content: center;align-items: center;}.spinner svg {position: absolute;width: var(--ownid-spinner-size);height: var(--ownid-spinner-size);overflow: visible;}.spinner .bg {stroke: var(--ownid-spinner-bg-color);opacity: var(--ownid-spinner-bg-opasity);}.spinner .sp {stroke-linecap: round;stroke: var(--ownid-spinner-color);animation: animation 2s cubic-bezier(0.61, 0.24, 0.44, 0.79) infinite;}.spinner .bg, .spinner .sp {fill: none;stroke-width: 15px;}.spinner .sp-svg {animation: rotate 2s cubic-bezier(0.61, 0.24, 0.44, 0.79) infinite;}@keyframes animation {0% {stroke-dasharray: 1 270;stroke-dashoffset: 70;}50% {stroke-dasharray: 80 270;stroke-dashoffset: 220;}100% {stroke-dasharray: 1 270;stroke-dashoffset: 70;}}@keyframes rotate {100% {transform: rotate(720deg);}}
                 </style>
                 <script type="text/javascript">
                   window.gigya = {};
                   window.OWNID_NATIVE_WEBVIEW = true;
                   window.ownid = async (...a) => ((window.ownid.q = window.ownid.q || []).push(a), {error: null, data: null});
                   function onJSException(ex) { document.location.href = 'ownid://on-js-exception?ex=' + encodeURIComponent(ex); }
                   function onJSLoadError() { document.location.href = 'ownid://on-js-load-error'; }
                   setTimeout(function () { if (!window.ownid?.sdk) onJSLoadError(); }, 10000);
                   window.onerror = (errorMsg) => onJSException(errorMsg);
                   var interval = setInterval(() => { if (window.ownid?.sdk) { clearInterval(interval); window.onerror = () => {}; } }, 500);
                 </script>
               </head>
               <body>
               <div class="spinner">
                 <svg viewBox="0 0 100 100"><circle class="bg" r="42.5" cx="50" cy="50"></circle></svg>
                 <svg class="sp-svg" viewBox="0 0 100 100"><circle class="sp" r="42.5" cx="50" cy="50"></circle></svg>
               </div>
               <script src="OWNID-CDN-URL" type="text/javascript" onerror="onJSLoadError()"></script>
               <script>ownid('start', { language: window.navigator.languages || 'en', animation: false });</script>
               </body>
               </html>
               """
        static let defaultBaseURL = "https://webview.ownid.com"
    }
    
    private let webView: WKWebView
    private var webBridge = OwnID.CoreSDK.createWebViewBridge()
    var wrappers = [any FlowWrapper]()
    var options: OwnID.EliteOptions?
    
    var resultPublisher = OwnID.CoreSDK.WebBridgePublisher()
    var webViewDelegate = OwnIDFlowWebViewDelegate()
    
    init() {
        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.websiteDataStore = WKWebsiteDataStore.default()
        webView = WKWebView(frame: .zero, configuration: webConfiguration)
        webView.customUserAgent = OwnID.CoreSDK.UserAgentManager.shared.SDKUserAgent
        webView.uiDelegate = webViewDelegate
        webView.navigationDelegate = webViewDelegate
    }
    
    func makeUIView(context: Context) -> WKWebView {
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        let appId = OwnID.CoreSDK.shared.appID ?? ""
        let env = OwnID.CoreSDK.shared.environment?.lowercased() ?? ""
        let envPart = ["dev", "staging", "uat"].contains(env) ? "\(env)." : ""
        let region = OwnID.CoreSDK.shared.region
        
        let webViewOptions = options?.webView
        if #available(iOS 16.4, *) { webView.isInspectable = webViewOptions?.webViewIsInspectable ?? false}
        let webViewSettings = OwnID.CoreSDK.shared.store.value.configuration?.webViewSettings
        
        let cdnBase = OwnID.CoreSDK.shared.store.value.configuration?.cdnBaseURL.absoluteString
            ?? ("https://cdn.\(envPart)ownid\(region).com/sdk")
        let cdnScript = cdnBase + "/" + appId
        let html = (webViewOptions?.html ?? webViewSettings?.html ?? Constants.defaultHtml)
            .replacingOccurrences(of: "OWNID-CDN-URL", with: cdnScript)
        let urlString = webViewOptions?.baseURL ?? webViewSettings?.baseURL ?? Constants.defaultBaseURL
        
        webView.loadHTMLString(html, baseURL: URL(string: urlString)!)
        
        let flowNamespaceHandler = webBridge.namespaceHandlers.first{ $0.name == .FLOW } as? OwnID.CoreSDK.WebBridgeFlow
        flowNamespaceHandler?.setWrappers(wrappers)
        webBridge.resultPublishers[.FLOW] = resultPublisher
        webBridge.injectInto(webView: webView, allowedOriginRules: [urlString])
        
        webViewDelegate.resultPublisher = resultPublisher
        webViewDelegate.wrappers = wrappers
    }
}

class OwnIDFlowWebViewDelegate: NSObject, WKUIDelegate, WKNavigationDelegate {
    private enum Constants {
        static let ownIdScheme = "ownid"
        static let jsExceptionHost = "on-js-exception"
        static let jsLoadErrorHost = "on-js-load-error"
    }
    
    var resultPublisher = OwnID.CoreSDK.WebBridgePublisher()
    var wrappers = [any FlowWrapper]()
    
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            OwnID.CoreSDK.logger.log(level: .debug, message: "Open the link from Flow \(url)", type: Self.self)
            UIApplication.shared.open(url)
        }
        return nil
    }
    
    func webView(_ webView: WKWebView, 
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url {
            if url.scheme == Constants.ownIdScheme {
                handleCustomURL(url)
                decisionHandler(.cancel)
                return
            }
        }
        decisionHandler(.allow)
    }

    private func handleCustomURL(_ url: URL) {
        if url.host == Constants.jsExceptionHost {
            if let query = url.query {
                let exception = query.replacingOccurrences(of: "ex=", with: "")
                let message = exception.removingPercentEncoding ?? "Unknown error"
                let errorModel = OwnID.CoreSDK.UserErrorModel(message: message)
                
                let payload = OwnID.OnErrorWrapper.Payload(error: .userError(errorModel: errorModel))
                let wrapper: OwnID.OnErrorWrapper? = OwnID.wrapperByAction(.onError, wrappers: wrappers)
                let flowEvent = OwnID.FlowEvent(action: .onError, wrapper: wrapper, payload: payload)
                resultPublisher.send(flowEvent)
                OwnID.CoreSDK.ErrorWrapper(error: .userError(errorModel: errorModel), type: Self.self).log()
            }
        } else if url.host == Constants.jsLoadErrorHost {
            let message = "JS load error \(url.absoluteString)"
            let errorModel = OwnID.CoreSDK.UserErrorModel(message: message)
            
            let payload = OwnID.OnErrorWrapper.Payload(error: .userError(errorModel: errorModel))
            let wrapper: OwnID.OnErrorWrapper? = OwnID.wrapperByAction(.onError, wrappers: wrappers)
            let flowEvent = OwnID.FlowEvent(action: .onError, wrapper: wrapper, payload: payload)
            resultPublisher.send(flowEvent)
            OwnID.CoreSDK.ErrorWrapper(error: .userError(errorModel: errorModel), type: Self.self).log()
        }
    }
}
