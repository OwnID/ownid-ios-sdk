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

Passkey setup is required baseline configuration for OwnID integrations. See the complete [Passkey Setup](docs/setup/passkeys.md) guide for AuthenticationServices availability, Associated Domains, AASA hosting, verification, and cache timing.

## Start Here

1. [Install the SDK](#install) for your flow or feature.
2. [Passkey Setup](docs/setup/passkeys.md) as baseline SDK setup.
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

- [DemoBase](DemoBase) shows standard SDK setup, Boost Flow, Elite Flow, Headless, Passkey Enrollment, and example identity-provider wiring.
- [DemoAdvanced](DemoAdvanced) shows customized Boost widgets, app-hosted operation UI, low-level API and operation scenarios, Headless, and Google provider wiring.

These apps are examples. Use public SDK source, published products, and documentation as the integration contract.

## Version Support

- **v4:** Current version, recommended for all integrations.
- **v3:** Maintenance mode. Receives only critical bug fixes and security updates; no new features.
- **v2:** Obsolete, deprecated, and no longer supported, including security updates.

## Data Safety

See [Data Safety](docs/setup/data-safety.md) for SDK data handling notes.

## Support

For integration help, contact [support@ownid.com](mailto:support@ownid.com).

## License

This SDK is distributed under the [Apache 2.0 license](LICENSE).
