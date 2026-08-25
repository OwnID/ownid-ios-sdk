![OwnIDSDK](Docs/logo.svg)
## OwnID iOS SDK
 
The [OwnID](https://www.ownid.com/) iOS SDK is a client library offering a secure and passwordless login alternative for your iOS applications. It leverages [Passkeys](https://www.passkeys.com/) to replace conventional passwords, fostering enhanced authentication methods. This SDK empowers users to seamlessly execute Registration and Login flows within their native iOS applications.

### Key components of the OwnID iOS SDK:

- **OwnID Core** - Provides fundamental functionalities such as SDK configuration, UI widgets, interaction with the iOS, and returning OwnID results to the iOS application. It also provide two variants:
   + **Boost** - designed to enhance your existing login and registration forms by adding OwnID widget as an add-on.
   + **Elite** - provides predefined authentication screens that can be easily customized with your brand’s look and feel.


- **OwnID Integration Component** - An optional extension of the Core SDK, designed for seamless integration with identity platforms on the native side. When present, it executes the actual registration and login processes into the identity platform.


### To integrate OwnID with your identity platform, you have three pathways:

- **[Direct Integration](Docs/sdk-direct-integration.md)** - Handle OwnID Response data directly without using the Integration component.

- **[Custom Integration](Docs/sdk-custom-integration.md)** - Develop your OwnID Integration component tailored to your identity platform.

- **Prebuilt Integration** - Utilize the existing OwnID SDK with a prebuilt Integration component. Options include:

   - **[OwnID Gigya](Docs/sdk-gigya.md)** - Expands Core SDK functionality by offering a prebuilt Gigya Integration, supporting Email/Password-based [Gigya Authentication](https://github.com/SAP/gigya-swift-sdk). It also includes the [OwnID WebView Bridge extension](Docs/sdk-gigya.md#add-ownid-webview-bridge), enabling native Passkeys functionality for Gigya Web Screen-Sets with OwnID Web SDK.

## Install

Swift Package Manager is the recommended installation method for OwnID iOS SDK v3.

Version 3 is distributed from a single repository tag, while its SDK components keep independent versions. Repository tag `3.11.0` contains OwnID Core `3.11.0` and OwnID Gigya `3.10.0`. Use the repository tag from the GitHub release when declaring the package; do not substitute an individual component's runtime version.

### Swift Package Manager

Add the package using the exact release version required by your app:

```swift
dependencies: [
    .package(
        url: "https://github.com/OwnID/ownid-ios-sdk.git",
        exact: "<version>"
    )
]
```

Then add the product your app target uses.

Core SDK:

```swift
.product(name: "OwnIDCoreSDK", package: "OwnID")
```

Gigya SDK:

```swift
.product(name: "OwnIDGigyaSDK", package: "OwnID")
```

`OwnIDGigyaSDK` depends on `OwnIDCoreSDK`. Add both products when your app imports both modules directly.

### CocoaPods Compatibility Fallback

<details>
<summary>CocoaPods</summary>

OwnID iOS SDK v3 versions through `3.10.0` may remain available from previously published CocoaPods specs. Starting with repository release `3.11.0`, new v3 podspec versions are not published to CocoaPods Trunk. For CocoaPods-only apps, use a pinned public Git tag as a compatibility fallback.

```ruby
target "YourApp" do
  pod "ownid-core-ios-sdk",
    :git => "https://github.com/OwnID/ownid-ios-sdk.git",
    :tag => "<version>"
end
```

If your app uses the Gigya SDK, declare both pods from the same repository tag so Gigya's exact Core dependency resolves from that release. For repository tag `3.11.0`, this installs OwnID Gigya `3.10.0` together with OwnID Core `3.11.0`:

```ruby
target "YourApp" do
  pod "ownid-core-ios-sdk",
    :git => "https://github.com/OwnID/ownid-ios-sdk.git",
    :tag => "<version>"

  pod "ownid-gigya-ios-sdk",
    :git => "https://github.com/OwnID/ownid-ios-sdk.git",
    :tag => "<version>"
end
```

</details>
   
## Additional Components

- **[OwnID WebView Bridge](Docs/sdk-webbridge-doc.md)** - A Core SDK component that introduces native Passkeys functionality to the OwnID Web SDK when running within a webview. Also, it suports the integration in Capacitor app.

## Advanced Configuration

Explore advanced configuration options in OwnID Core iOS SDK by referring to the [Advanced Configuration](Docs/sdk-advanced-configuration.md) documentation.

## Demo Applications

This repository hosts various OwnID Demo applications, each showcasing integration scenarios:

- **Direct Handling of OwnID Response**: `DirectDemo` target.

- **Custom Integration**: `IntegrationDemo` target.

- **Gigya Integration Demos**:
   - `GigyaDemo` target provides an example of Gigya integration using SwiftUI.
   - `UIKitInjectionDemo` target provides an example of Gigya integration using UIKit.

- **Gigya Web Screen-Sets with WebView Bridge Demo**: `ScreensetsDemo` target.

You can run these demo apps on a physical device or a simulator.

## Supported Languages
The OwnID SDK has built-in support for multiple languages. The SDK loads translations in runtime and selects the best language available. The list of currently supported languages can be found [here](https://i18n.prod.ownid.com/langs.json).

The SDK will also make the RTL adjustments if needed. If the user's mobile device uses a language that is not supported, the SDK displays the UI in English.

## Data Safety
The OwnID SDK collects data and information about events inside the SDK using Log Data. This Log Data does not include any personal data that can be used to identify the user such as username, email, and password. It does include general information like the device Internet Protocol (“IP”) address, device model, operating system version, time and date of events, and other statistics.

Log Data is sent to the OwnID server using an encrypted process so it can be used to collect OwnID service statistics and improve service quality. OwnID does not share Log Data with any third party services.

## Feedback
We'd love to hear from you! If you have any questions or suggestions, feel free to reach out by creating a GitHub issue.

## License

```
Copyright 2025 OwnID INC.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

```
