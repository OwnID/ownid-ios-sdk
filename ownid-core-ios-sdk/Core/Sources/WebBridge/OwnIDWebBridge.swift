//
//  OwnIDWebBridge.swift
//  private-ownid-core-ios-sdk
//
//  Created by user on 12.10.2023.
//

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
    }    
    
    public class OwnIDWebBridge: NSObject, WKScriptMessageHandler {
        private let JSEventHandler = "ownIDJSHandler"
        
        private var webView: WKWebView?
        private var namepace: WebNameSpace?
        
        public func injectInto(webView: WKWebView) {
            self.webView = webView
            
            let contentController = webView.configuration.userContentController
            
            let JSInterface = getJSInterface()
            
            let userScript = WKUserScript(source: JSInterface, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page)
            contentController.addUserScript(userScript)
            
            contentController.removeScriptMessageHandler(forName: JSEventHandler)
            contentController.add(self, name: JSEventHandler)
        }
        
        private func getJSInterface() -> String {
            let actions = JSAction.allCases.map({ $0.rawValue })
            let feature = JSNamespace.FIDO.rawValue
            let JSInterface =  """
                window.__ownidNativeBridge = {
                    getNamespaces: function() { return '{\"\(feature)\": \(actions)}'; },
                    invokeNative: function(namespace, action, callbackPath, params) {
                        window.webkit.messageHandlers.\(JSEventHandler).postMessage({method: 'invokeNative', data: { namespace, action, callbackPath, params }});
                    }
                }
                """
            return JSInterface
        }
        
        public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let messageBody = message.body as? [String: Any] else {
                let message = OwnID.CoreSDK.ErrorMessage.dataIsMissing
                CoreErrorLogWrapper.coreLog(error: .userError(errorModel: OwnID.CoreSDK.UserErrorModel(message: message)), type: Self.self)
                return
            }
            
            guard let data = messageBody["data"] as? [String: Any], let method = messageBody["method"] as? String else {
                let message = OwnID.CoreSDK.ErrorMessage.dataIsMissing
                CoreErrorLogWrapper.coreLog(error: .userError(errorModel: OwnID.CoreSDK.UserErrorModel(message: message)), type: Self.self)
                return
            }
            
            switch method {
            case "invokeNative":
                guard let jsonData = try? JSONSerialization.data(withJSONObject: data, options: .prettyPrinted),
                      let JSDataModel = try? JSONDecoder().decode(JSDataModel.self, from: jsonData) else {
                    let message = OwnID.CoreSDK.ErrorMessage.dataIsMissing
                    CoreErrorLogWrapper.coreLog(error: .userError(errorModel: OwnID.CoreSDK.UserErrorModel(message: message)), type: Self.self)
                    return
                }
                
                switch JSDataModel.namespace {
                case .FIDO:
                    namepace = OwnIdGigyaFido()
                    namepace?.invoke(webView: webView ?? WKWebView(), action: JSDataModel.action, params: JSDataModel.params ?? "") { [weak self] result in
                        self?.invokeCallback(callbackPath: JSDataModel.callbackPath, and: result)
                    }
                }
            default:
                break
            }
        }
        
        private func invokeCallback(callbackPath: String, and result: String) {
            let JS = "\(callbackPath)(\(result));"
            
            OwnID.CoreSDK.logger.log(level: .information, message: "InvokeCallback \(JS)", Self.self)
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                self.webView?.evaluateJavaScript(JS)
            }
        }
    }    
}
