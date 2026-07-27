---
name: ownid-ios-integration
description: >-
  Use this skill when adding, migrating, or reviewing OwnID iOS SDK v4
  integration in a client iOS app, including Swift Package Manager dependencies
  or CocoaPods git-tag fallback, passkey setup, SDK configuration, namespace
  handles, context, providers, SwiftUI Boost widgets, Elite Flow, Passkey
  Enrollment, WebBridge, UI customization, app-hosted Operation UI, and
  v3-to-v4 migration.
---

# OwnID iOS Integration

Use this skill for client iOS apps that consume the published OwnID iOS SDK.

This skill is repository-local: relative source links assume the skill lives at
`.agents/skills/ownid-ios-integration/` inside the OwnID iOS SDK repository. If
the skill is copied elsewhere, resolve those links against the public SDK
repository tag for the SDK version being integrated; the copied skill path
itself may not exist in the client app.

## Start Here

1. Read [intake.md](references/intake.md) before editing.
2. Inspect the host app and build an Integration Brief from facts already in
   the project; ask only for missing values that block a safe decision.
3. Use the intake routing rules to load only the baseline and task-specific
   references needed for the selected work.
4. Treat [enable-passkeys.md](references/enable-passkeys.md) as baseline OwnID
   SDK setup for new integrations and migrations.
5. Verify dependency versions and exact call shapes against the matching SDK
   release.
6. Finish with [validation.md](references/validation.md).

## Reference Routing

- [install.md](references/install.md): Swift Package Manager, CocoaPods, and
  compatibility.
- [enable-passkeys.md](references/enable-passkeys.md): required baseline
  AuthenticationServices, Associated Domains, AASA, and platform passkey setup.
- [configuration.md](references/configuration.md): SDK initialization,
  environment, region, root URL/custom domain, language, and logging.
- [namespace-handles.md](references/namespace-handles.md): SDK namespace
  handles, derived handles, and context/provider binding mechanics.
- [context.md](references/context.md): choose OwnID runtime context values:
  `.start(...)`, `.fromToken(...)`, `accountDisplayName`, `withContext`,
  `setContext`, and `clearContext`.
- [providers.md](references/providers.md): register app-owned provider
  callbacks for session creation, password authentication, Google/social
  sign-in, and track Sign in with Apple capability and tenant setup.
- [boost-flow.md](references/boost-flow.md): add OwnID SwiftUI widgets to
  existing native login or registration forms while keeping app-owned fallback
  paths.
- [elite-flow.md](references/elite-flow.md): SDK-managed WKWebView that loads
  an OwnID-hosted page where the OwnID Web SDK runs; native SDK/WebBridge
  plumbing forwards hosted events to app-owned handoff callbacks.
- [passkey-enrollment.md](references/passkey-enrollment.md): add a passkey to
  the current signed-in account using a valid OwnID access token.
- [webbridge.md](references/webbridge.md): attach native WebBridge to an
  app-owned WKWebView whose app/tenant page loads the OwnID Web SDK and needs
  native passkeys, context, stored user, social sign-in, or auth providers.
- [ui-customization.md](references/ui-customization.md): themes, colors,
  localization, widgets, and app-hosted Operation UI for login ID collection
  and verification.
- [migration-v3-to-v4.md](references/migration-v3-to-v4.md): move an existing
  v3 integration to the v4 SDK boundary: new products, changed integration
  responsibilities, removed packaged integrations/UI surfaces, and updated
  flow/WebBridge surfaces.

## Working Rules

- Use public OwnID README/docs for product flows and terminology, production SDK
  API/source and published release metadata for exact types, behavior,
  lifecycle, and dependency contracts, and maintained demos for working
  host-app composition. Reconcile all of them against the selected SDK release.
- Include intended integrator surfaces demonstrated by the docs or maintained
  demos, including app-hosted Operation UI, when production SDK types and
  behavior support the pattern.
- Copy OwnID-published source-only helpers unchanged. Keep app-owned
  dependencies, configuration, and provider registration outside the helper.
- Preserve the host app's existing auth, session, navigation, loading, error,
  logging, analytics, and dependency-management patterns.
- Add the smallest required OwnID product.
- Keep secrets and environment-specific private values out of source.
- Track backend, OwnID Console, Apple Developer, Google Cloud, Associated
  Domains, AASA hosting, signing, and production configuration as external work
  when the host repository or task does not own them.
- Use the decision rules in `intake.md`; continue from project evidence for
  reversible implementation details.

## Handoff

Report the OwnID surface used, files changed, checks run, manually verified flow
or verification gap, and remaining external setup.
