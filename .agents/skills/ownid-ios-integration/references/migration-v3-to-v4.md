# Migration From v3 To v4

Use this reference when migrating an existing iOS app from OwnID SDK v3 to OwnID
SDK v4. Treat migration as an integration redesign at the SDK boundary, not as a
version-only update.

Public migration overview: `../../../../docs/upgrade/v3-to-v4.md`.

## Contents

- [Migration Principle](#migration-principle)
- [Read Before Editing](#read-before-editing)
- [Audit The v3 Integration](#audit-the-v3-integration)
- [Dependency Mapping](#dependency-mapping)
- [Initialization And Configuration](#initialization-and-configuration)
- [Map v3 Integration Responsibilities](#map-v3-integration-responsibilities)
- [Flow Surface Mapping](#flow-surface-mapping)
- [WebBridge Migration](#webbridge-migration)
- [Passkey Enrollment Migration](#passkey-enrollment-migration)
- [UI Customization Migration](#ui-customization-migration)
- [Migration Audit Checklist](#migration-audit-checklist)
- [Validation Guidance](#validation-guidance)
- [Decisions To Confirm](#decisions-to-confirm)

## Migration Principle

Version 4 keeps the product flows but changes ownership:

- OwnID SDK owns runtime initialization, flow APIs, passkey operations,
  SwiftUI widgets, Passkey Enrollment, and WebBridge.
- The client app owns identity-platform integration, password authentication,
  app-session creation, social sign-in SDK setup, fallback auth, registration
  submission, and navigation.
- Replace packaged v3 integrations and v3 Core/Gigya flow views with the
  appropriate v4 callbacks, handoffs, providers, flows, and SwiftUI UI.

First identify the user journey the app needs, then wire that journey to the
smallest v4 surface.

## Read Before Editing

Load only the references that match the v3 inventory and target v4 surface:

- `install.md` for SwiftPM products, CocoaPods fallback use, and compatibility
  gates.
- `configuration.md` for `OwnID.initialize*` startup.
- `providers.md` for provider setup and source-only provider helpers.
- `boost-flow.md` for native login/registration forms with SDK widgets.
- `elite-flow.md` for OwnID-hosted WebView flows.
- `webbridge.md` for app-owned `WKWebView` pages that load and initialize the
  OwnID Web SDK.
- `passkey-enrollment.md` and `enable-passkeys.md` for post-login enrollment
  and iOS passkey prerequisites.
- `ui-customization.md` for supported v4 SwiftUI customization.
- `validation.md` for the smallest meaningful post-migration checks.

Use v4 docs for target product flows, production API/source for exact calls and
lifecycle behavior, and maintained DemoBase/DemoAdvanced implementations for
working host-app composition.

## Audit The v3 Integration

Before changing files, inspect the host app and make a local migration inventory.
A temporary v4 dependency upgrade plus compilation can help expose mechanical
v3 API breakages, but it does not prove the migrated integration is correct.

Search for these high-signal v3 surfaces first. Treat the list as migration
triage, not as an exhaustive v3 API catalog:

```text
OwnIDCoreSDK
OwnIDGigyaSDK
ownid-core-ios-sdk
ownid-gigya-ios-sdk
OwnID.CoreSDK
OwnID.GigyaSDK
OwnIDConfiguration.plist
configureWebBridge
createWebViewBridge
OwnIDWebBridge
OwnID.FlowsSDK
LoginView
RegisterView
LoginView.ViewModel
RegisterView.ViewModel
integrationEventPublisher
LoginPublisher
RegistrationPublisher
enrollCredential
OwnID.GigyaSDK.defaultLoginIdPublisher
OwnID.GigyaSDK.defaultAuthTokenPublisher
GigyaSDK.registrationViewModel
GigyaSDK.loginViewModel
GigyaSDK.createRegisterView
GigyaSDK.createLoginView
ownIdData
```

Classify each hit by behavior:

- **Boost login/registration:** v3 flow views, ViewModels, Combine publishers,
  `OwnID.FlowsSDK.*View`, `createRegisterView`, or `ownIdData` submitted with
  registration.
- **Packaged Gigya:** `OwnIDGigyaSDK`, `ownid-gigya-ios-sdk`,
  `OwnID.GigyaSDK.*`, Gigya Screen-Sets bridge helpers.
- **Direct/custom integration:** app code that handles OwnID response payloads
  directly or implements an Integration Component.
- **Elite:** `OwnID.CoreSDK.start(...)`, options/page-action handlers, or
  OwnID-hosted web flow startup.
- **WebBridge:** `OwnID.CoreSDK.createWebViewBridge(...)`,
  `OwnID.GigyaSDK.configureWebBridge()`, Gigya Screen-Sets bridge, Capacitor or
  `WKWebView` bridge setup.
- **Enrollment:** `OwnID.CoreSDK.enrollCredential(...)`, login-ID publishers,
  auth-token publishers, or Gigya default token/login-ID helpers.
- **UI customization:** v3 visual configuration, UIKit hosting/injection around
  v3 views, custom flow view wrappers, or Combine-driven widget state.

If the inventory shows backend/session contract changes, get the product
decision before implementing that boundary.

## Dependency Mapping

Replace v3 dependencies with the smallest v4 product:

| v3 surface | v4 replacement |
| --- | --- |
| SwiftPM `OwnIDCoreSDK` / `import OwnIDCoreSDK` | `OwnIDCore` / `import OwnIDCore` |
| SwiftPM `OwnIDGigyaSDK` / `import OwnIDGigyaSDK` | remove; copy/register source-only Gigya provider helper only when the app already uses SAP CDC/Gigya |
| CocoaPods `ownid-core-ios-sdk` | prefer SwiftPM `OwnIDCore`; for CocoaPods-only apps, use the pinned public git-tag fallback from `install.md` |
| CocoaPods `ownid-gigya-ios-sdk` | remove; use `OwnIDCore` plus source-only Gigya provider helper when needed |
| v3 Core/Gigya flow views and ViewModels | `OwnIDSwiftUI` widgets |

Use `OwnIDSwiftUI` only when the app renders SDK SwiftUI widgets, operation UI,
themes, colors, or reusable SwiftUI components. It depends on `OwnIDCore`; add
`OwnIDCore` directly when the target imports Core APIs, names Core
callback/response types, or project conventions require explicit direct
products.

Respect the compatibility gates and host-project policies in `install.md`
before changing dependencies or platform settings.
OwnID SDK v4 uses the pinned git-tag CocoaPods fallback described in
`install.md`. Use a normal Trunk declaration when release metadata confirms v4
pod publication. Keep deployment target, Swift language mode, Xcode/signing
requirements, and unrelated packages/pods aligned with the host app; treat any
required baseline upgrade as separate migration work.

## Initialization And Configuration

Replace v3 SDK configuration with one v4 initialization path during app
startup:

```swift
OwnID.logger { builder in
    // Optional: configure according to the app's logging policy.
}

OwnID.initialize { configuration in
    configuration.appID = "<OWNID_APP_ID>"
    configuration.env = .prod
    configuration.region = .us
}
```

Supported v4 sources:

- `OwnID.initialize { ... }` for programmatic config.
- `OwnID.initializeFromJSON { configuration in configuration.json = ... }`.
- `OwnID.initializeFromFile { configuration in configuration.fileURL = ... }`.

Migration rules:

- Replace `OwnID.CoreSDK.configure(...)`,
  `OwnID.GigyaSDK.configure(...)`, and v3 user-facing SDK metadata setup with
  `OwnID.initialize*`.
- Recreate config using v4 keys: `appID` or `appId`, `env`, `region`,
  `rootURL` or `rootUrl`, optional `languages`.
- Default v4 plist file name is `OwnIDConfig.plist`; recreate configuration
  with v4 keys.
- Initialize once before providers, widgets, flows, enrollment, or WebBridge.
- Use `OwnID.setLanguage(...)` only when the app intentionally overrides
  process language tags.

## Map v3 Integration Responsibilities

Version 3 Boost integration boundaries and Elite providers do not have one
mechanical version 4 replacement. Use the public
[migration mapping](../../../../docs/upgrade/v3-to-v4.md#migrate-integration-responsibilities)
to classify each responsibility before choosing callbacks, handoffs, or
providers. Choose the version 4 journey first, keep app-owned responsibilities
at their existing boundaries, and register only capabilities that the selected
integration invokes.

For selected provider capabilities, open `providers.md` for exact parameter,
result, availability, and scope contracts.

Migration rules:

- Register providers after successful `OwnID.initialize*` and before starting
  SDK functionality that may call them.
- Preserve existing app-owned authentication, session types, storage, and
  lifecycle policies. Route provider inputs through those boundaries and
  extend them only when the selected journey requires a new app-owned contract.
- Sign in with Apple is provided by Core; register Google only when the app
  owns Google sign-in setup.
- Use `withProviders { ... }` as a one-flow, screen, or WebBridge provider
  override when behavior must differ from top-level providers.
- Keep fallback password login and manual registration paths unless the product
  owner explicitly removes them.

For SAP Customer Data Cloud/Gigya apps:

- Remove `OwnIDGigyaSDK` and old Gigya pods/products.
- Keep the SAP CDC Swift SDK only if the app already owns it.
- Copy the v4 source-only helper from
  `../../../../Providers/OwnIDGigyaProviders.swift`.
- Register it after both OwnID and Gigya are initialized:

```swift
OwnID.setProviders { registrar in
    registrar.gigyaProviders(gigya: Gigya.sharedInstance())
}
```

Gigya providers are source-only helper wiring, not a Swift package product or
pod.

## Flow Surface Mapping

### Boost Login And Registration

Replace v3 flow views, ViewModels, and Combine publishers with v4 SwiftUI
widgets from `OwnIDSwiftUI`:

- Login screen:
  `OwnIDLoginWidget(onLogin: ..., loginID: email, onError: ..., onCancel: ...)`.
- Registration screen:
  `OwnIDCreatePasskeyWidget(onLogin: ..., onNewPasskey: ..., onReset: ..., loginID: email)`.

Keep the app's existing form validation, submit buttons, password fallback,
registration endpoint, navigation, and session owner.

Critical rules:

- Pass the visible login ID field into the widget.
- In callbacks, treat `response.loginID.id` as authoritative and copy it back
  to the form because OwnID may normalize it.
- On login success, use `response.session` when present; otherwise route
  `response.accessToken` and `response.sessionPayload` to the app session
  boundary.
- On create-passkey success, submit `response.ownIdData(forLoginID: ...)`
  unchanged with the matching registration request when it returns a value. It
  is opaque and may be `nil`.
- Clear pending create-passkey state when the user changes login ID, the widget
  calls `onReset`, or registration completes.
- Keep the existing successful registration policy unless the backend already
  supports generated-password or passwordless behavior.
- For UIKit apps, host the SwiftUI widget through the app's existing hosting
  pattern.

Open `boost-flow.md` before editing Boost code.

### Elite Flow

Replace v3 `OwnID.CoreSDK.start(...)` and page-action APIs with v4 Elite Flow.
Open `elite-flow.md` before editing Elite code.

- Use `EliteFlowContext` for optional WebView display options and event
  handlers.
- Keep the returned controller while the flow is active; use `abort(reason:)`
  for semantic cancellation.
- Hand `accessToken` and `ownIdData` to existing app/backend owners. Create
  sessions in view callbacks only when that is where the app already owns
  session creation.
- Replace old v3 page-action wrappers or webflow implementation details with
  the corresponding v4 surfaces.

### Direct Or Custom Integration

There is no v4 Integration Component equivalent. Choose the matching v4
surface:

- Use Boost widgets when the app keeps native login/registration forms.
- Use providers plus Elite/WebBridge when authentication is web-hosted.

If neither supported surface matches the existing custom journey, stop after
classifying its responsibilities and report that the target integration is
outside this skill's supported surfaces.

## WebBridge Migration

Version 3 injected a bridge into an existing `WKWebView`. Version 4 creates a
fresh bridge from the current namespace and explicitly attaches it. Open
`webbridge.md` before editing WebBridge code.

- Replace `OwnID.CoreSDK.createWebViewBridge(...)` and
  `OwnID.GigyaSDK.configureWebBridge()` with
  `OwnID.webBridge.create().attach(...)`.
- Attach before loading content, or reload after successful attach.
- Create a new `WebBridge` per `WKWebView` session.
- Pass explicit trusted origins when server configuration may not be available
  yet. Avoid global wildcard origins in production.
- Scope context before `create()` when the page needs a specific session, login
  ID, or access token. Use provider overrides when this WKWebView session must
  differ from top-level providers.
- Use bridge plugin customization through the v4 plugin registry APIs.
- Detach according to lifecycle when the page/session ends.

The app-owned web page must load and initialize OwnID Web SDK before it can use
native bridge capabilities. Native WebBridge does not create the WKWebView,
load the page, or own the web content.

## Passkey Enrollment Migration

Replace v3 Credential Enrollment APIs and `OwnID.CoreSDK.enrollCredential` with
v4 Passkey Enrollment. Open `passkey-enrollment.md` before editing enrollment
code.

Migration rules:

- Enrollment is post-login for the currently signed-in user.
- v4 needs an OwnID access token for that user; replace v3 login-ID/auth-token
  publishers with the v4 access-token path.
- If the enrollment path has a proof token, pass it through the
  `PasskeyEnrollFlowContext` route.
- Check iOS passkey prerequisites: iOS 16 runtime behavior, Associated Domains
  entitlement, AASA `webcredentials`, app target, provisioning, tenant/domain
  alignment, and simulator/device limitations.
- Treat availability failures and user cancellation as fallback states, not as
  account failure.

## UI Customization Migration

Discard v3 flow-view customization:

- visual config tied to `OwnID.FlowsSDK.*View`;
- UIKit injection around old views;
- Combine publisher chains used only to drive old widget state;
- custom wrappers around `OwnID.GigyaSDK.create*View`.

Recreate the required v4 SwiftUI customization:

- widget parameters: `theme`, `widgetStrings`, `showSpinner`, `position`, view
  model ownership;
- modifiers/slots: `.iconButton`, `.checkmark`, `.orText`;
- shared `OwnIDTheme` and `OwnIDColors`;
- app-hosted operation UI via `appHostedComponent` and `OwnIDOperationView`;
- language configuration, `BoostWidgetStrings`, and operation UI strings.

Use v4 SwiftUI customization surfaces for appearance changes.

## Migration Audit Checklist

Before ending the migration, verify by inspection that:

- No v3 OwnID products, pods, private pods, or imports remain in app targets.
- No app code imports `OwnIDCoreSDK` or `OwnIDGigyaSDK`.
- No code calls `OwnID.CoreSDK`, `OwnID.GigyaSDK`, v3 flow views, v3 view
  models, or v3 Combine publishers.
- OwnID initializes once from v4 config before providers and flows.
- Version 3 integration responsibilities were classified with the public
  migration mapping before choosing version 4 callbacks, handoffs, or providers.
- Only providers used by the selected integration are registered, at the correct
  global or scoped boundary.
- Configured provider callbacks go through the existing app-owned integration
  boundary; unrelated app-owned flows remain separate.
- Any migrated Boost registration path submits only current matching
  `ownIdData`.
- Any migrated WebBridge attaches before page load/reload and uses trusted
  origins.
- Any migrated Passkey Enrollment path uses a current OwnID access token.
- Fallback password/manual registration flows remain available unless their
  removal was explicitly approved.
- UI customization uses v4 SwiftUI APIs and app-hosted Operation UI where the
  migrated journey needs it.

## Validation Guidance

When the task allows validation, run the smallest meaningful host-app check:

- package/pod resolution or target build for dependency/config-only changes;
- affected iOS app build after code migration;
- targeted simulator/device flow check for login, registration, WebBridge, or
  enrollment;
- inspect Associated Domains/AASA/passkey setup when passkey behavior changed.

Report unrelated validation failures separately with the command and failing
owner.

## Decisions To Confirm

Get confirmation when migration changes:

- removing password fallback or manual registration;
- changing backend registration/session contracts;
- changing identity provider, tenant, region, app ID, domains, or secrets;
- replacing UIKit-hosted v3 flows with a different user journey;
- raising deployment target, Swift language mode, Xcode, signing, package, or
  pod baselines;
- changing SAP CDC/Gigya configuration or schema;
- using unpublished SDK versions, private podspecs, branches, or local package
  paths.
