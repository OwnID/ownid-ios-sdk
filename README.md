![OwnIDSDK](Docs/logo.svg)
## OwnID iOS SDK
 
The [OwnID](https://ownid.com/) iOS SDK is a client library written in Swift that provides a passwordless login alternative for your iOS application by using [Passkeys](https://www.passkeys.com/) to replace the traditional password. Integrating the SDK with your app allows the user to perform Registration and Login flows in a native iOS application.

The OwnID iOS SDK consists of a **[Core](Docs/sdk-core-doc.md)** module along with modules that are specific to an identity platform like Gigya. The Core module provides core functionality like setting up an OwnID configuration, performing network calls to the OwnID server, interacting with an iOS, and checking and returning results to the iOS application. The following modules extend the Core module for a specific identify management system:

- **[OwnID Gigya iOS SDK](Docs/sdk-gigya-doc.md)** - Extends Core SDK functionality by providing integration with Email/Password-based [Gigya Authentication](https://github.com/SAP/gigya-swift-sdk).

The OwnID iOS SDK supports Swift >= 5.1, and works with iOS 14 and above.

## WebView Integration

You can use OwnID iOS SDK WebView Bridge to seamlessly integrate the native capabilities of the OwnID iOS SDK into the OwnID WebSDK. Check **[OwnID iOS SDK WebView Bridge](Docs/sdk-webbridge-doc.md)** for detailed steps.

## Demo applications
This repository contains OwnID Demo application sources for different types of integrations:
- Gigya Integration Demo
- Gigya UIKit Injection Demo
- Gigya Screen Sets Integration Demo

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
Copyright 2023 OwnID INC.

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
