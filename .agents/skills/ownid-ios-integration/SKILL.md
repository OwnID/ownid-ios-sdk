---
name: ownid-ios-integration
description: Use this skill when adding, migrating, or reviewing OwnID iOS SDK v4 integration in a client iOS app, including Swift Package Manager dependencies or CocoaPods git-tag fallback, passkey setup, SDK configuration, namespace handles, context, providers, SwiftUI Boost widgets, Elite Flow, Passkey Enrollment, WebBridge, Headless flows, UI customization, and v3-to-v4 migration.
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
5. Verify dependency versions and snippets against the public SDK release tag
   for the version being integrated.
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
- [headless.md](references/headless.md): app-owned UI that orchestrates OwnID
  discovery, auth requirements, passkey auth, verification, login, and optional
  enrollment.
- [ui-customization.md](references/ui-customization.md): themes, colors,
  localization, widgets, and app-hosted operation UI.
- [migration-v3-to-v4.md](references/migration-v3-to-v4.md): move an existing
  v3 integration to the v4 SDK boundary: new products, provider-based identity
  integration, removed packaged integrations/UI surfaces, and updated
  flow/WebBridge surfaces.

## Guardrails

- Use only public SDK APIs and published package metadata as the host-app
  integration contract.
- OwnID-published source-only helpers may contain SDK-owned internal hooks. Copy
  helpers unchanged first and treat those hooks as helper implementation
  details.
- Treat demo apps as examples, not contracts.
- Preserve the host app's existing auth, session, navigation, loading, error,
  logging, analytics, and dependency-management patterns.
- Add the smallest required OwnID product.
- Keep secrets and environment-specific private values out of source.
- Treat backend, OwnID Console, Apple Developer, Google Cloud, Associated
  Domains, AASA hosting, signing, publishing, tags, remotes, and production
  configuration as explicit external work.
- If public behavior is unclear and the assumption affects auth/session
  behavior, secrets, backend/console setup, dependency versions, signing, or
  another externally visible contract, stop and ask.

## Handoff

Report the OwnID surface used, files changed, checks run, manually verified flow
or verification gap, and remaining external setup.
