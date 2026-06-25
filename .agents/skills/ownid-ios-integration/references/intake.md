# Intake

Use this reference before choosing an OwnID iOS SDK v4 integration surface or
editing a client app. The goal is to collect enough host-app facts to make a
narrow integration plan and load only the task-specific references needed for
the selected work.

Start from the app workflow that must change, then map it to the smallest
matching OwnID surface.

## Contents

- [Ground Rules](#ground-rules)
- [Integration Brief](#integration-brief)
- [Reference Routing](#reference-routing)
- [Surface Selection](#surface-selection)
- [Stop And Ask](#stop-and-ask)

## Ground Rules

- Inspect the host app source, Xcode project/workspace, package files,
  entitlements, Info.plist, docs, and existing auth code before proposing
  changes.
- Treat backend APIs, session model, identity provider, dependency management,
  signing, entitlements, schemes, and release configuration as app-owned
  contracts.
- Use public OwnID SDK v4 APIs, public API comments, published package/pod
  metadata, and the public SDK release tag as the integration contract. Use
  docs as guidance and report stale docs when they disagree with code or
  metadata. Demo apps are examples.
- Reuse existing app configuration/dependency patterns when they are clear.
- Ask before changing backend contracts, tenant/console setup, Associated
  Domains/AASA hosting, Apple Developer setup, Google Cloud or other external
  identity-provider setup, signing, deployment target, Swift version, package
  manager, or production configuration.

## Integration Brief

Before implementation, produce a short Integration Brief from facts found in
the project. Ask the developer only for missing values that block a safe
decision. If an existing value is found, state where it was found and ask
whether to reuse it when changing it would affect environment, auth/session
behavior, passkeys, external setup, or production configuration.

Use these fields as prompts, not as mandatory sections:

- **Target**: app target, bundle IDs, schemes/configurations, deployment
  target, Swift/toolchain version, UI stack, dependency manager, and requested
  OwnID SDK version/tag.
- **Workflow**: login, registration/create account, account security/passkey
  enrollment, web-hosted auth, migration, UI customization, or a combination.
- **SDK setup**: configuration source, `appID`, environment (`.prod` by
  default; `.uat` only when specified), region, root URL/custom domain, language
  policy, and logging policy.
- **Dependencies**: `OwnIDCore`, `OwnIDSwiftUI`, and any source-only provider
  helper or app-owned provider dependency.
- **Auth/session boundary**: login ID types, password path,
  registration/session endpoints, token/session storage, logout/refresh, and
  where OwnID results are handed to app code.
- **Passkeys**: relying-party domain, Associated Domains/AASA owner, App ID
  prefix or signed `application-identifier`, bundle IDs, provisioning/signing
  coverage, and who can approve external setup.
- **Providers**: `sessionCreate`, `passwordAuthenticate`, Sign in with Apple,
  Google, or other provider needs and whether global providers are enough.
- **UI/WKWebView**: SwiftUI/UIKit ownership, WKWebView owner, hosted URL,
  trusted origins, and lifecycle/controller owner.
- **Migration**: existing v3 products/imports/surfaces and the first workflow
  to migrate.
- **Validation**: smallest build/check the app can run, manual flow access, and
  external setup that cannot be validated locally.
- **Open questions**: decisions that are unsafe to infer.

For non-trivial work, keep the brief compact:

```text
OwnID Integration Brief
- Platform/target:
- Existing OwnID version or none:
- Requested SDK version: latest / exact <version>
- Workflow(s):
- Selected OwnID surface(s):
- SDK configuration:
- Dependency choice:
- Auth/session handoff:
- Providers/social:
- Passkeys:
- WebBridge:
- UI customization:
- Migration scope:
- Validation allowed:
- Values found in app that need confirmation:
- Missing values to ask for:
- External setup not owned by this repo:
```

When real values are unavailable, ask whether to stop and wait, use explicit
placeholders, reuse values already found in the app, or wire values through the
app's existing environment/config system.

## Reference Routing

Load the smallest set that matches the Integration Brief:

- Always read `install.md`, `configuration.md`, and `enable-passkeys.md` for a
  new SDK integration or full migration. Passkey platform setup is baseline
  OwnID setup even if the first visible screen is not a passkey screen.
- Read `namespace-handles.md` when scoped providers or scoped context may be
  involved.
- Read `context.md` when a selected API needs login-ID auth, access-token auth,
  or account display context.
- Read `providers.md` when the integration needs app-owned callbacks such as
  session creation, password authentication, Sign in with Apple, Google, SAP
  CDC/Gigya notes, or other identity-provider behavior.
- Read exactly the selected surface file: `boost-flow.md`, `elite-flow.md`,
  `passkey-enrollment.md`, `webbridge.md`, `headless.md`, or
  `ui-customization.md`.
- Read `migration-v3-to-v4.md` only for existing v3 integrations.

Keep the loaded references scoped to the selected work.

## Surface Selection

Choose the smallest surface that matches the app workflow:

- **Boost Flow**: existing native login or registration screen stays in app UI
  and adds OwnID SwiftUI widgets.
- **Elite Flow**: OwnID-hosted auth page runs in an SDK-managed `WKWebView`, and
  the app handles terminal callbacks.
- **Headless**: app owns all UI and drives OwnID discovery/auth APIs directly.
- **Passkey Enrollment**: signed-in user adds a passkey using a valid OwnID
  access token.
- **WebBridge**: app-owned WKWebView loads an app/tenant page with OwnID Web SDK
  and needs native capabilities through the bridge.
- **UI Customization**: app changes SDK UI appearance, strings, or widgets
  without changing flow semantics.

If the requested work spans multiple surfaces, split the plan and ask which
workflow to implement first when scope is not explicit.

## Stop And Ask

Stop before editing when any blocking value or decision is missing:

- SDK version/tag or dependency approval path;
- required SDK configuration values or whether placeholders are acceptable;
- session handoff model, registration contract for `ownIdData`, or backend API
  changes;
- relying-party domain, Associated Domains/AASA hosting, App ID prefix or signed
  `application-identifier`, bundle IDs, or provisioning profiles;
- Apple Developer, Google Cloud, OwnID Console, SAP CDC/Gigya, or other
  external tenant setup;
- UI ownership choice between Boost, Elite, Headless, or WebBridge;
- unsupported/no-passkey device behavior that affects product requirements;
- changes to deployment target, Swift version, package manager, signing,
  entitlements, production config, or release process;
- validation requiring real credentials, device setup, console access, or
  remote configuration.
