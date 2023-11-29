//
//  OwnIDGigyaWebBridge.swift
//  private-ownid-gigya-ios-sdk
//
//  Created by user on 12.10.2023.
//

import Gigya
import WebKit

extension OwnID.GigyaSDK {
    class OwnIDGigyaWebBridge<T: GigyaAccountProtocol>: GigyaWebBridge<T> {
        let webBridge = OwnID.CoreSDK.OwnIDWebBridge()
        
        override func attachTo(webView: WKWebView, viewController: UIViewController, pluginEvent: @escaping (GigyaPluginEvent<T>) -> Void) {
            super.attachTo(webView: webView, viewController: viewController, pluginEvent: pluginEvent)
            
            webBridge.injectInto(webView: webView)
        }
    }
}
