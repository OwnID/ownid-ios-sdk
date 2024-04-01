# OwnID iOS SDK WebView Bridge - WebView Integration

The OwnID iOS SDK WebView Bridge, an integral part of the OwnID Core iOS SDK, empowers the OwnID Web SDK to leverage the native capabilities of the OwnID iOS SDK. 

The bridge facilitates the injection of JavaScript code, enabling communication between the OwnID Web SDK and the native OwnID iOS SDK.

To get more information about the OwnID iOS SDK, please refer to the [OwnID iOS SDK](../README.md) documentation.

## Table of contents
* [Before You Begin](#before-you-begin)
* [WebView Bridge components](#webView-bridge-components)
* [Adding WebView Bridge](#adding-webview-bridge)
   + [Utilizing Prebuilt Integration-specific WebView Bridge](#utilizing-prebuilt-integration-specific-webview-bridge)
   + [Manual Integration of WebView Bridge](#manual-integration-of-webview-bridge)

---

## Before You Begin
Before incorporating OwnID iOS SDK WebView Bridge into your iOS application, ensure that you have already incorporated the OwnID iOS SDK. You can find step-by-step instructions in the [OwnID iOS SDK](../README.md) documentation.

Additionally, make sure you have integrated the [OwnID Web SDK is added into WebView](https://docs.ownid.com).

## WebView Bridge components

The OwnID iOS SDK WebView Bridge comprises the following components:

 - **Native Passkey Support**. 
 
Ensure that you enable passkey authentication in your iOS application by following the steps outlined in the Enable Passkey Authentication section of the OwnID documentation.

## Adding WebView Bridge
You have two primary options for integrating the OwnID WebView Bridge into your application:

### Utilizing Prebuilt Integration-specific WebView Bridge

Currently OwnID SDK provides prebuilt WebView Bridge for [OwnID Gigya iOS SDK](sdk-gigya.md#add-ownid-webview-bridge) for seamless integration with Gigya Web Screen-Sets with OwnID Web SDK.

### Manual integration of the OwnID WebView Bridge

To manually integrate the OwnID WebView Bridge into your WebView, follow these steps:

1. Create an instance of the OwnID iOS SDK. Detailed instructions can be found in the [OwnID iOS SDK](../README.md).

2. Inject the OwnID WebView Bridge into your Webview. This is typically done during the creation of the WebView and before loading its content.

```swift
let webBridge = OwnID.CoreSDK.OwnIDWebBridge()
webBridge.injectInto(webView: webView)
```
