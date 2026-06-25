# Migration from Version 3 to Version 4

This page is a migration overview for moving an iOS app from OwnID SDK version 3 to version 4. It is not a one-to-one API replacement table; use it to choose the version 4 integration path, then follow the linked version 4 documentation for detailed setup and examples.

## Contents

- [Key Differences Between Version 3 and Version 4](#key-differences-between-version-3-and-version-4)
- [Dependency Name Changes](#dependency-name-changes)
- [Update SDK Dependencies](#update-sdk-dependencies)
- [Initialize and Configure OwnID](#initialize-and-configure-ownid)
- [Migrate Integration to Providers](#migrate-integration-to-providers)
- [Migrate User Journeys](#migrate-user-journeys)
- [Update UI Customization](#update-ui-customization)

## Key Differences Between Version 3 and Version 4

Version 4 keeps the main product flows, but changes the SDK boundary. The SDK now focuses on OwnID runtime, flows, widgets, WebBridge, and provider contracts. Identity-platform integrations are app-owned and are wired through providers.

| Area | Version 3 | Version 4 |
| --- | --- | --- |
| Core SDK | iOS 14+; Swift 5.1+; runtime plus flow UI | iOS 13+; Swift 6; runtime, providers, flows, Passkey Enrollment, WebBridge |
| Flow UI | `OwnID.FlowsSDK.*View`, ViewModels, publishers | Use `OwnIDSwiftUI` |
| SwiftUI integration | Part of Core/Gigya flow UI | Separate `OwnIDSwiftUI` product; iOS 13+; Swift 6; native SwiftUI UI |
| UIKit integration | Demo/injection patterns around v3 flow views | Use `OwnIDSwiftUI` or app-owned hosting |
| Boost Flow | Flow views, ViewModels, publishers | Boost Flow widgets and callbacks; see [Migrate Boost Flow](#migrate-boost-flow) |
| Elite Flow | Start/page-action APIs | Elite Flow context, callbacks, and app-owned controller; see [Migrate Elite Flow](#migrate-elite-flow) |
| Passkey Enrollment | Credential Enrollment APIs | Passkey Enrollment; see [Migrate Passkey Enrollment](#migrate-passkey-enrollment) |
| WebBridge | Bridge injection APIs | Explicit create/attach lifecycle, trusted origins, and provider/context setup |
| Gigya SDK integration | `ownid-gigya-ios-sdk` / `OwnIDGigyaSDK`; native Gigya integration; Gigya Screen-Sets setup | Use providers and the source-only helper; see [Providers](../setup/providers.md#sap-customer-data-cloud-gigya) |
| Direct/custom integration | Direct response handling or Integration Component | Choose the matching v4 flow or feature: Boost Flow, Elite Flow, WebBridge, or Headless; wire providers where that flow or feature needs app-owned capabilities |

## Dependency Name Changes

Version 4 changes the dependency and module names. Update the dependency entry and the imported module names together; dependency managers will not migrate version 3 names automatically.

For current Swift Package Manager and CocoaPods fallback snippets, see [Install](../../README.md#install).

| Manager | Version 3 | Version 4 |
| --- | --- | --- |
| Swift Package Manager | `OwnIDCoreSDK` product / `import OwnIDCoreSDK` | `OwnIDCore` product / `import OwnIDCore` |
| Swift Package Manager | `OwnIDGigyaSDK` product / `import OwnIDGigyaSDK` | Use `OwnIDCore` with the source-only SAP Customer Data Cloud helper. |
| CocoaPods | `pod "ownid-core-ios-sdk"` / `import OwnIDCoreSDK` | Prefer Swift Package Manager with `OwnIDCore`; CocoaPods-only apps can pin `OwnIDCore` from the public git tag. |
| CocoaPods | `pod "ownid-gigya-ios-sdk"` / `import OwnIDGigyaSDK` | Remove the packaged Gigya SDK; use `OwnIDCore` with the source-only SAP Customer Data Cloud helper when needed. |

## Update SDK Dependencies

Use the smallest version 4 SDK product that covers the flow your app needs:

- Add `OwnIDCore` for SDK configuration, providers, Elite Flow, Headless, Passkey Enrollment, and WebBridge.
- Add `OwnIDSwiftUI` for Boost Flow widgets, themes, colors, and reusable UI components. It depends on Core.
- Remove version 3 SDK entries: `ownid-core-ios-sdk` / `ownid-gigya-ios-sdk` for CocoaPods, or `OwnIDCoreSDK` / `OwnIDGigyaSDK` products for Swift Package Manager. Replace version 3 imports such as `import OwnIDCoreSDK` and `import OwnIDGigyaSDK`.

For Swift Package Manager and CocoaPods fallback snippets, start with [Install](../../README.md#install).

## Initialize and Configure OwnID

Version 3 apps commonly initialize the SDK with `OwnID.CoreSDK.configure(...)`, `OwnID.GigyaSDK.configure(...)`, and `OwnIDConfiguration.plist`.

In version 4, initialize OwnID once during app startup with one of the standard configuration sources:

- configure from code;
- configure from a JSON string;
- configure from a plist file.

The default configuration file is now `OwnIDConfig.plist`. Configuration still includes the OwnID application ID, environment, region, and language options, but it is no longer tied to a direct/custom/Gigya integration setup.

Do not reuse a version 3 configuration file as-is; recreate it using the version 4 configuration keys. Remove version 3 redirection and logging keys such as `OwnIDRedirectionURL` and `EnableLogging`; configure logging with `OwnID.logger` when needed.

See [SDK Configuration](../setup/configuration.md) for the supported initialization APIs and configuration keys.

## Migrate Integration to Providers

Version 4 moves identity-platform work to providers. Instead of using an OwnID Integration Component or packaged Gigya SDK, the app registers the app-owned capabilities that OwnID functionality may call:

- [`sessionCreate`](../setup/providers.md#session-create) creates or restores the app session from the authenticated login ID, OwnID Access Token, and session payload.
- [`passwordAuthenticate`](../setup/providers.md#password-authenticate) verifies the user's password through the app's authentication system or identity provider; passwords are not sent to OwnID.
- social sign-in capabilities connect OwnID functionality to app-owned social setup. [Sign in with Google](../setup/providers.md#sign-in-with-google) is registered as a provider; [Sign in with Apple](../setup/providers.md#sign-in-with-apple) is built into `OwnIDCore` and requires Apple capability and tenant setup.
- source-only provider helpers, such as Gigya, register common provider sets for a specific identity platform.

Register providers after OwnID initialization and before starting functionality that needs them. Because providers are usually shared app capabilities, most apps should register them on the top-level `OwnID` namespace handle, typically during startup. For detailed provider setup, including Google, Sign in with Apple, and SAP Customer Data Cloud (Gigya), see [Providers](../setup/providers.md).

Version 3 account-registration providers and integration registration hooks do not have a direct version 4 provider equivalent. Keep account creation in the app-owned registration path for the version 4 flow or feature you choose.

Providers replace the app-owned identity-platform integration hooks from version 3, not the whole user journey. If the version 3 integration owned custom UI or state-machine behavior, choose the version 4 flow or feature that matches that journey: [Boost Flow](../flows/boost-flow.md), [Elite Flow](../flows/elite-flow.md), [WebBridge](../integration/webbridge.md), or [Headless](../flows/headless.md).

## Migrate User Journeys

### Migrate Boost Flow

Boost Flow still adds OwnID to existing native login and account-creation experiences. The migration changes the UI entry points and callback model.

Version 3 apps use OwnID flow views, view models, and publishers from the Core/Gigya SDK. Version 4 moves app-facing native UI to `OwnIDSwiftUI` and exposes Boost Flow through SwiftUI login and create-passkey widgets.

The app still keeps its existing login and registration forms. The login widget reports authenticated login results, and the create-passkey widget reports either a create-passkey result for the registration path or an existing-account login result.

See [Boost Flow](../flows/boost-flow.md) for the version 4 flow model and examples. See [Boost Widget Customization](../customization/boost-widgets.md) for widget appearance and state ownership.

### Migrate Elite Flow

Elite Flow still runs an OwnID-hosted authentication experience in an SDK-managed WebView. The migration changes how the app starts the flow and receives hosted-page events.

Version 3 Elite uses start/page-action APIs. Version 4 starts Elite Flow with an explicit `EliteFlowContext`. Hosted-page outcomes are delivered through event callbacks, and the running flow is represented by an app-owned controller.

See [Elite Flow](../flows/elite-flow.md) for the version 4 start API, callback semantics, and controller ownership.

### Migrate Passkey Enrollment

Version 4 keeps post-login credential enrollment as Passkey Enrollment.

Version 3 starts enrollment through Credential Enrollment APIs with login ID and `authToken` input. Version 4 enrollment requires an OwnID Access Token for the signed-in user, and the SDK handles passkey creation and enrollment for that account.

See [Passkey Enrollment](../flows/passkey-enrollment.md) for the version 4 enrollment setup and examples.

### Migrate WebBridge

WebBridge still connects OwnID Web SDK pages inside an app-owned `WKWebView` to native OwnID capabilities. Version 4 changes setup from injection-style APIs to explicit bridge creation and attachment.

Version 3 apps inject a bridge into the `WKWebView` from the SDK. Version 4 apps create a fresh `WebBridge` from the current OwnID runtime, attach it to a trusted `WKWebView`, then load or reload the page after attachment succeeds.

Version 4 also makes WebBridge setup more explicit: configure trusted origins, providers, plugins, and context before using the bridge, and create a new `WebBridge` for each `WKWebView` session.

See [WebBridge](../integration/webbridge.md) for allowed origins, setup, lifecycle, and provider/context setup.

## Update UI Customization

Version 4 UI customization is tied to the version 4 UI features:

- use [Themes and Colors](../customization/themes-and-colors.md) for shared theme and color-token setup;
- use [Localization](../customization/localization.md) for OwnID UI text.

Do not carry over version 3 visual configuration directly. Recreate only the customization that the version 4 SwiftUI SDK supports.
