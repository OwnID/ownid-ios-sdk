# OwnID iOS SDK WebView Bridge - WebView Integration
The OwnID iOS SDK WebView Bridge is a part of OwnID Core iOS SDK that enables OwnID Web SDK to use native capabilities of the OwnID iOS SDK.
OwnID WebView Bridge injects JavaScript code that can be used by OwnID Web SDK to communicate with native OwnID iOS SDK.

To get more information about the OwnID iOS SDK, please refer to the [OwnID iOS SDK](../README.md) documentation.

## Table of contents
* [Before You Begin](#before-you-begin)
* [Adding WebView Bridge](#adding-webview-bridge)
* [Manual integration of the OwnID WebView Bridge](#manual-integration-of-the-ownid-webview-bridge)

---

## Before You Begin
Before incorporating OwnID iOS SDK WebView Bridge into your iOS application, ensure that you have already incorporated the OwnID iOS SDK. You can find step-by-step instructions in the [OwnID iOS SDK](../README.md) documentation.

Additionally, make sure you have integrated the [OwnID Web SDK is added into WebView](https://docs.ownid.com).

## Adding WebView Bridge
You have two primary options for integrating the OwnID WebView Bridge into your application:
- Utilize pre-built integration-specific OwnID WebView Bridge provided by the OwnID SDKs:
  + [OwnID Gigya iOS SDK](sdk-gigya-doc.md#add-ownid-webview-bridge) for seamless integration with Gigya Screen-Sets.
- Use manual integration of the OwnID WebView Bridge tailored to your identity management system.

## Manual integration of the OwnID WebView Bridge
To add the OwnID WebView Bridge to your WebView, add the following:

```swift
let webBridge = OwnID.CoreSDK.OwnIDWebBridge()
webBridge.injectInto(webView: webView)
```
