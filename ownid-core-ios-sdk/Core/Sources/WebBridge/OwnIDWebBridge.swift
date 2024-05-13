import Foundation
import WebKit

extension OwnID.CoreSDK {
    enum JSNamespace: String, Decodable {
        case FIDO
    }
    
    enum JSAction: String, Decodable, CaseIterable {
        case isAvailable, create, get
    }
    
    struct JSDataModel: Decodable {
        let namespace: JSNamespace
        let action: JSAction
        let callbackPath: String
        let params: String?
        let metadata: JSMetadata?
    }
    
    struct JSMetadata: Decodable {
        var category: JSMetadataCategory?
        let context: String?
        let siteUrl: String?
        let widgetId: String?
        
        enum CodingKeys: CodingKey {
            case category, context, siteUrl, widgetId
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            self.category = try? container.decodeIfPresent(JSMetadataCategory.self, forKey: .category) ?? .general
            self.context = try container.decodeIfPresent(String.self, forKey: .context)
            self.siteUrl = try container.decodeIfPresent(String.self, forKey: .siteUrl)
            self.widgetId = try container.decodeIfPresent(String.self, forKey: .widgetId)
        }
    }
    
    enum JSMetadataCategory: String, Decodable {
        case register
        case login
        case link
        case recovery
        case general
    }
    
    public class OwnIDWebBridge: NSObject, WKScriptMessageHandler {
        private let JSEventHandler = "__ownidNativeBridgeHandler"
        
        private var webView: WKWebView?
        private var namespace: WebNameSpace?
        private var origins = [URL]()
        
        public func injectInto(webView: WKWebView, allowedOriginRules: Set<String> = []) {
            self.webView = webView
            
            let contentController = webView.configuration.userContentController
            
            let JSInterface = getJSInterface()
            
            let userScript = WKUserScript(source: JSInterface, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .page)
            contentController.addUserScript(userScript)
            
            contentController.removeScriptMessageHandler(forName: JSEventHandler)
            contentController.add(self, name: JSEventHandler)
            
            let allOrigins = OwnID.CoreSDK.shared.store.value.configuration?.origins.union(allowedOriginRules)
                .compactMap { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0 != "*" }
                .compactMap { URL(string: $0) }
                .compactMap({ url in
                    switch url.scheme {
                    case nil:
                        return URL(string:"https://\(url)")
                    case "https" where url.scheme?.caseInsensitiveCompare("https") == .orderedSame:
                        return url
                    default:
                        return nil
                    }
                })
            origins = allOrigins ?? []
        }
        
        private func getJSInterface() -> String {
            let actions = JSAction.allCases.map({ $0.rawValue })
            let feature = JSNamespace.FIDO.rawValue
            let JSInterface =  """
                window.__ownidNativeBridge = {
                    getNamespaces: function getNamespaces() { return '{\"\(feature)\": \(actions)}'; },
                    invokeNative: function invokeNative(namespace, action, callbackPath, params, metadata) {
                        try {
                            window.webkit.messageHandlers.\(JSEventHandler).postMessage({method: 'invokeNative', data: { namespace, action, callbackPath, params, metadata }});
                        } catch (error) {
                            console.error(error);
                            setTimeout(function errorHandler() {
                                eval(callbackPath + '(false);');
                            });
                        }
                    }
                }
                """
            return JSInterface
        }
        
        public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let messageBody = message.body as? [String: Any] else {
                let message = OwnID.CoreSDK.ErrorMessage.dataIsMissing
                ErrorWrapper(error: .userError(errorModel: UserErrorModel(message: message)), type: Self.self).log()
                return
            }
            
            guard let data = messageBody["data"] as? [String: Any], let method = messageBody["method"] as? String else {
                let message = OwnID.CoreSDK.ErrorMessage.dataIsMissing
                ErrorWrapper(error: .userError(errorModel: UserErrorModel(message: message)), type: Self.self).log()
                return
            }
            
            switch method {
            case "invokeNative":
                guard let jsonData = try? JSONSerialization.data(withJSONObject: data, options: .prettyPrinted),
                      let JSDataModel = try? JSONDecoder().decode(JSDataModel.self, from: jsonData) else {
                    let message = OwnID.CoreSDK.ErrorMessage.dataIsMissing
                    ErrorWrapper(error: .userError(errorModel: UserErrorModel(message: message)), type: Self.self).log()
                    return
                }
                
                switch JSDataModel.namespace {
                case .FIDO:
                    namespace = OwnIDWebBridgeFido()
                    let bridgeContext = OwnIDWebBridgeContext(webView: webView ?? WKWebView(),
                                                              sourceOrigin: message.frameInfo.request.url,
                                                              allowedOriginRules: origins,
                                                              isMainFrame: message.frameInfo.isMainFrame)
                    namespace?.invoke(bridgeContext: bridgeContext,
                                      action: JSDataModel.action,
                                      params: JSDataModel.params ?? "",
                                      metadata: JSDataModel.metadata) { [weak self] result in
                        self?.invokeCallback(callbackPath: JSDataModel.callbackPath, and: result)
                    }
                }
            default:
                break
            }
        }
        
        private func invokeCallback(callbackPath: String, and result: String) {
            let JS = "\(callbackPath)(\(result));"
            
            OwnID.CoreSDK.logger.log(level: .information, message: "InvokeCallback \(JS)", type: Self.self)
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                self.webView?.evaluateJavaScript(JS)
            }
        }
    }    
}
