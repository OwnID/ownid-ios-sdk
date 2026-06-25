<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/logo.svg">
  <source media="(prefers-color-scheme: light)" srcset="docs/images/logo-dark.svg">
  <img alt="OwnID" src="docs/images/logo-dark.svg" width="260">
</picture>

# OwnID iOS SDK

[![OwnID Core iOS SDK version](https://badgen.net/github/tag/OwnID/ownid-ios-sdk?label=OwnID%20Core%20iOS%20SDK)](https://github.com/OwnID/ownid-ios-sdk/releases/latest)
[![OwnID SwiftUI iOS SDK version](https://badgen.net/github/tag/OwnID/ownid-ios-sdk?label=OwnID%20SwiftUI%20iOS%20SDK)](https://github.com/OwnID/ownid-ios-sdk/releases/latest)

OwnID iOS SDK helps apps add passkey-first authentication, account verification, and passkey enrollment while keeping the app in control of its users, sessions, and identity-provider setup.

## Install

Use the smallest SDK that covers the flow or feature your app needs.

| Add | Provides |
| --- | --- |
| Core SDK<br/>`OwnIDCore` | SDK configuration, providers, built-in Sign in with Apple support, Elite Flow, Headless, Passkey Enrollment, WebBridge, and passkey authentication flows. |
| SwiftUI SDK<br/>`OwnIDSwiftUI` | Boost widgets, SDK-provided SwiftUI operation UI, app-hosted operation UI, themes, colors, and reusable UI components. Depends on Core. |

Both SDK products require:

- iOS 13.0+
- Swift 6
- Xcode 16.0+

### Swift Package Manager

Add the package:

```swift
dependencies: [
    .package(url: "https://github.com/OwnID/ownid-ios-sdk.git", from: "<latest-version>")
]
```

Then add the product your app target uses.

Core SDK:

```swift
.product(name: "OwnIDCore", package: "OwnID")
```

SwiftUI SDK:

```swift
.product(name: "OwnIDSwiftUI", package: "OwnID")
```

> [!NOTE]
> `OwnIDSwiftUI` depends on `OwnIDCore`. Add `OwnIDCore` separately only when your app target imports both modules directly.

### CocoaPods Compatibility Fallback

<details>
<summary>CocoaPods</summary>

For CocoaPods-only apps, use a pinned public git tag as a compatibility fallback.

```ruby
target "YourApp" do
  pod "OwnIDCore",
    :git => "https://github.com/OwnID/ownid-ios-sdk.git",
    :tag => "<version>"
end
```

If your app uses `OwnIDSwiftUI`, declare both pods from the same tag:

```ruby
target "YourApp" do
  pod "OwnIDCore",
    :git => "https://github.com/OwnID/ownid-ios-sdk.git",
    :tag => "<version>"

  pod "OwnIDSwiftUI",
    :git => "https://github.com/OwnID/ownid-ios-sdk.git",
    :tag => "<version>"
end
```

</details>

## Enable Passkeys

OwnID uses Apple's [AuthenticationServices](https://developer.apple.com/documentation/authenticationservices) framework for passkey creation and authentication. Platform passkeys work on iOS 16 and higher.

### Associated Domains

Passkeys require your app and relying party domain to be associated with Apple's `webcredentials` service.

Use the same relying party domain that OwnID uses for passkey requests.

In Xcode, add the Associated Domains capability to the app target, then add:

```text
webcredentials:<relying-party-domain>
```

Host an Apple App Site Association file at:

```text
https://<relying-party-domain>/.well-known/apple-app-site-association
```

The file must be publicly available over HTTPS, return `HTTP 200`, use a JSON content type, avoid redirects, stay under 128 KB, and have no `.json` extension.

```json
{
  "webcredentials": {
    "apps": [
      "<APP_ID_PREFIX>.<BUNDLE_ID>"
    ]
  }
}
```

Add each app target that should use passkeys as `<APP_ID_PREFIX>.<BUNDLE_ID>`. This value must match the signed app's `application-identifier` entitlement. The App ID prefix is usually the Apple Team ID; if it differs, use the prefix from the signed app or provisioning profile.

See Apple's [Supporting associated domains](https://developer.apple.com/documentation/xcode/supporting-associated-domains) and [Associated Domains Entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.associated-domains) for the platform requirements and validation behavior.

## Start Here

1. [Install the SDK](#install) for your flow or feature.
2. [Enable Passkeys](#enable-passkeys) as baseline SDK setup.
3. [Configure OwnID](docs/setup/configuration.md) before using the SDK.
4. [Register providers](docs/setup/providers.md) required by the OwnID functionality and identity systems your app uses.
   Implement app-specific providers in your app; copy source-only helpers from [`Providers/`](Providers/) only when the Providers guide calls for them.

After setup, choose the integration path that matches the screen or user journey you are building.

| App need | Use | SDK product | Start with |
| --- | --- | --- | --- |
| Add OwnID to an existing native login screen | Boost Login Widget | SwiftUI SDK | [Boost Flow](docs/flows/boost-flow.md) |
| Add create-passkey to account creation | Boost Create Passkey Widget | SwiftUI SDK | [Boost Flow](docs/flows/boost-flow.md) |
| Use hosted OwnID authentication UI in the app | Elite Flow | Core SDK | [Elite Flow](docs/flows/elite-flow.md) |
| Build fully custom native authentication UI | Headless | Core SDK | [Headless](docs/flows/headless.md) |
| Add a passkey for a signed-in user | Passkey Enrollment | Core SDK | [Passkey Enrollment](docs/flows/passkey-enrollment.md) |
| Connect OwnID Web SDK inside an app `WKWebView` | WebBridge | Core SDK | [WebBridge](docs/integration/webbridge.md) |

> [!TIP]
> Migrating from OwnID SDK version 3? Start with [Migration from Version 3 to Version 4](docs/upgrade/v3-to-v4.md).

The full documentation map is in [Documentation](docs/README.md).

## Examples

- [DemoBase](Demo/DemoBase) shows standard SDK setup, Boost Flow, Elite Flow, Headless, Passkey Enrollment, and example identity-provider wiring.
- [DemoAdvanced](Demo/DemoAdvanced) shows customized Boost widgets, app-hosted operation UI, low-level API and operation scenarios, Headless, and Google provider wiring.

These apps are examples, not the public API contract. Use the SDK source, published products, and documentation as the contract.

## Data Safety

OwnID SDK collects SDK event and log data to operate the service, measure reliability, and improve product quality. This log data does not include personal data that directly identifies the user, such as username, email, or password.

Log data may include general technical information such as IP address, device model, operating system version, event time, and SDK statistics. It is sent to OwnID using encrypted transport and is not shared with third-party services.

The SDK may keep lightweight local user state, such as the last used login identifier and authentication method, to keep SDK experiences consistent across app sessions.

Your app remains responsible for its own account data, session data, consent, and App Store privacy disclosures.

## Support

For integration help, contact [support@ownid.com](mailto:support@ownid.com).

## License

This SDK is distributed under the [Apache 2.0 license](LICENSE).
