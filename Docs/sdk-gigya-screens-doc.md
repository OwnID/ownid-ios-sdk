# OwnID Gigya-Screen-Sets iOS Integration Instructions
The OwnID Gigya-Screen-Sets iOS SDK integrates with an iOS app that uses [Gigya Screen-Sets](https://github.com/SAP/gigya-swift-sdk/tree/main/GigyaSwift#using-screen-sets) for authentication. If your app uses native Email/Password-based [Gigya Authentication](https://github.com/SAP/gigya-swift-sdk/) without Screen-Sets, use the **[OwnID Gigya-iOS SDK](../README.md)** instead.

The OwnID Gigya-Screen-Sets SDK provides a passwordless login alternative for your iOS application by using cryptographic keys to replace the traditional password.

## Before You Begin
Before incorporating OwnID into your app, you need to create an OwnID application and integrate it with your Gigya project. For details, see [OwnID-Gigya Integration Basics](gigya-integration-basics.md).

You should also ensure you have done everything to [integrate Gigya's service into your project](https://github.com/SAP/gigya-swift-sdk).

## Create URL Type (Custom URL Scheme)
The redirection URL determines where the user lands once they are done using their browser to interact with the OwnID web app. This ensures that the screen set view is closed after the user is logged in or registered. The custom scheme of this redirection URL must be defined in two places:
- In the [OwnID Console](http://console.ownid.com), where the custom scheme is the value of the Redirection URL field of your OwnID application.
- In Xcode, where you navigate to **Info > URL Types**, and then use the **URL Schemes** field to specify the redirection URL scheme.

For example, if your redirection URL scheme is `com.myapp.demo://myhost`, then you must specify this scheme in both places.

## Working with Gigya Screen-Sets

You can work with Gigya Screen-Sets as usual. No custom code is required.
