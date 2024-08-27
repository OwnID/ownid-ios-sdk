import Foundation
import WebKit
import Combine

public protocol WebBridgeResult { }

extension OwnID.CoreSDK {
    public typealias WebBridgePublisher = PassthroughSubject<WebBridgeResult, Never>
    
    public enum Namespace: String, Decodable {
        case FIDO
        case METADATA
        case STORAGE
    }
    
    enum Action: String, Decodable, CaseIterable {
        case isAvailable
        case create
        case get
        case onAccountNotFound
        case onLogin
        case onClose
        case onError
        case setLastUser
        case getLastUser
    }
    
    struct JSDataModel: Decodable {
        let namespace: Namespace
        let action: Action
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
    
    struct OwnIDWebBridgeContext {
        var webView: WKWebView
        var sourceOrigin: URL?
        var allowedOriginRules: [URL]
        var isMainFrame: Bool
        var resultPublisher: WebBridgePublisher?
    }
    
    struct JSError: Codable {
        let error: JSErrorData
    }
    
    struct JSErrorData: Codable {
        let type: String?
        let errorMessage: String?
        let errorCode: String?
    }
    
    public class OwnIDWebBridge: NSObject, WKScriptMessageHandler {
        enum Constants {
            static let JSEventHandler = "__ownidNativeBridgeHandler"
            static let notificationName = "ConfigurationFetched"
        }
        
        private var webView: WKWebView?
        private var namespace: WebNamespace?
        private var allowedOriginRules: Set<String> = []
        private var origins = [URL]()
        
        private var namespaces = [WebNamespace]()
        private let includeNamespaces: [Namespace]?
        private let excludeNamespaces: [Namespace]?
        
        var resultPublishers = [Namespace: WebBridgePublisher]()
        
        init(includeNamespaces: [Namespace]? = nil, excludeNamespaces: [Namespace]? = nil) {
            self.includeNamespaces = includeNamespaces
            self.excludeNamespaces = excludeNamespaces
        }
        
        public func injectInto(webView: WKWebView, allowedOriginRules: Set<String> = []) {
            self.webView = webView
            self.allowedOriginRules = allowedOriginRules
            
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(setupOrigins),
                                                   name: Notification.Name(Constants.notificationName),
                                                   object: nil)
            
            let contentController = webView.configuration.userContentController
            
            let JSInterface = getJSInterface()
            
            let userScript = WKUserScript(source: JSInterface, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .page)
            contentController.addUserScript(userScript)
            
            contentController.removeScriptMessageHandler(forName: Constants.JSEventHandler)
            contentController.add(self, name: Constants.JSEventHandler)
            
            setupOrigins()
        }
        
        @objc private func setupOrigins() {
            DispatchQueue.main.async {
                let configOrigins = OwnID.CoreSDK.shared.store.value.configuration?.origins ?? []
                let allOrigins = configOrigins.union(self.allowedOriginRules)
                    .compactMap { URL(string: $0) }
                    .compactMap { url in
                        switch url.scheme {
                        case nil:
                            return URL(string:"https://\(url)")
                        case "https" where url.scheme?.caseInsensitiveCompare("https") == .orderedSame:
                            return url
                        default:
                            return nil
                        }
                    }
                
                self.origins = allOrigins
            }
        }
        
        private func setupNamespaces() {
            namespaces = [OwnIDWebBridgeFido(), OwnIDWebBridgeMetadata(), OwnIDWebBridgeStorage()]
            
            if let includeNamespaces {
                namespaces = []
                
                includeNamespaces.forEach { namespace in
                    switch namespace {
                    case .FIDO:
                        namespaces.append(OwnIDWebBridgeFido())
                    case .METADATA:
                        namespaces.append(OwnIDWebBridgeMetadata())
                    case .STORAGE:
                        namespaces.append(OwnIDWebBridgeStorage())
                    }
                }
            }
            
            if let excludeNamespaces {
                excludeNamespaces.forEach { namespace in
                    if let index = namespaces.firstIndex(where: { $0.name == namespace }) {
                        namespaces.remove(at: index)
                    }
                }
            }
        }
        
        private func getJSInterface() -> String {
            setupNamespaces()
            
            let namespacesString = namespaces.map { namespace in
                let actions = namespace.actions.map { $0.rawValue }
                return "\"\(namespace.name.rawValue)\": \(actions)"
            }.joined(separator: ", ")

            let JSInterface =  """
                window.__ownidNativeBridge = {
                    getNamespaces: function getNamespaces() { return '{\(namespacesString)}'; },
                    invokeNative: function invokeNative(namespace, action, callbackPath, params, metadata) {
                        try {
                            window.webkit.messageHandlers.\(Constants.JSEventHandler).postMessage({method: 'invokeNative', data: { namespace, action, callbackPath, params, metadata }});
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
                let message = OwnID.CoreSDK.ErrorMessage.dataIsMissingError(dataInfo: "messageBody")
                ErrorWrapper(error: .userError(errorModel: UserErrorModel(message: message)), type: Self.self).log()
                return
            }
            
            guard let data = messageBody["data"] as? [String: Any], let method = messageBody["method"] as? String else {
                let message = OwnID.CoreSDK.ErrorMessage.dataIsMissingError(dataInfo: "method")
                ErrorWrapper(error: .userError(errorModel: UserErrorModel(message: message)), type: Self.self).log()
                return
            }
            
            switch method {
            case "invokeNative":
                guard let jsonData = try? JSONSerialization.data(withJSONObject: data, options: .prettyPrinted),
                      let JSDataModel = try? JSONDecoder().decode(JSDataModel.self, from: jsonData) else { 
                    let message = OwnID.CoreSDK.ErrorMessage.dataIsMissingError()
                    ErrorWrapper(error: .userError(errorModel: UserErrorModel(message: message)), type: Self.self).log()
                    return
                }
                
                let bridgeContext = OwnIDWebBridgeContext(webView: webView ?? WKWebView(),
                                                          sourceOrigin: message.frameInfo.request.url,
                                                          allowedOriginRules: origins,
                                                          isMainFrame: message.frameInfo.isMainFrame,
                                                          resultPublisher: resultPublishers[JSDataModel.namespace])
                
                switch JSDataModel.namespace {
                case .FIDO:
                    let namespace = OwnIDWebBridgeFido()
                    self.namespace = namespace
                case .METADATA:
                    let namespace = OwnIDWebBridgeMetadata()
                    self.namespace = namespace
                case .STORAGE:
                    let namespace = OwnIDWebBridgeStorage()
                    self.namespace = namespace
                }
                
                let metadata = JSDataModel.metadata
                let category: EventCategory
                switch metadata?.category ?? .general {
                case .general:
                    category = .general
                case .register:
                    category = .registration
                case .login:
                    category = .login
                case .link:
                    category = .link
                case .recovery:
                    category = .recovery
                }
                OwnID.CoreSDK.eventService.sendMetric(.trackMetric(action: .webBridge(name: JSDataModel.namespace.rawValue,
                                                                                      type: JSDataModel.action.rawValue),
                                                                   category: category,
                                                                   context: metadata?.context,
                                                                   siteUrl: metadata?.siteUrl,
                                                                   webViewOrigin: bridgeContext.sourceOrigin?.absoluteString,
                                                                   widgetId: metadata?.widgetId))
                
                namespace?.invoke(bridgeContext: bridgeContext,
                                  action: JSDataModel.action,
                                  params: JSDataModel.params ?? "",
                                  metadata: JSDataModel.metadata) { [weak self] result in
                    self?.invokeCallback(callbackPath: JSDataModel.callbackPath, and: result)
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
