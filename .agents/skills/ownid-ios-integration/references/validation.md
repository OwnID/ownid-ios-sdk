# Validation

Use this reference at the end of an OwnID iOS SDK v4 integration. Validate the
changed host-app behavior and its directly dependent OwnID surfaces.

## Contents

- [Boundary](#boundary)
- [Minimal Local Checks](#minimal-local-checks)
- [Reference-Backed Checks](#reference-backed-checks)
- [Surface Checks](#surface-checks)
- [External Validation Gaps](#external-validation-gaps)
- [Handoff](#handoff)

## Boundary

- Validate the selected flow and terminology against OwnID docs, exact API and
  lifecycle behavior against production source and published release metadata,
  and host-app composition against maintained demos where they cover the same
  surface.
- Validate package/pod usage, host-app configuration, entitlements, and
  app-owned auth/session contracts touched by the integration.
- Record backend, tenant, Apple Developer, identity-provider, Associated
  Domains/AASA, signing, provisioning, secrets, production, analytics, and
  navigation dependencies that remain outside the local change.
- If required external setup is missing, report it as a gap instead of
  inventing values.

## Minimal Local Checks

Choose the smallest host-app check that proves the touched iOS surface
compiles:

- Xcode app target: run the app's normal build, typically:

  ```shell
  xcodebuild -workspace <App>.xcworkspace -scheme <Scheme> \
    -destination 'platform=iOS Simulator,name=<Device>' build
  ```

  Use the equivalent `-project` command when the app has no workspace.
- Swift Package Manager host app/package: run the normal package resolve/build,
  such as `xcodebuild -resolvePackageDependencies` followed by the target build,
  or `swift build` for a pure package target.
- CocoaPods dependency changes: run `pod install` only when dependency files
  changed, then build the workspace.
- Swift/provider/source-helper changes: run the app build plus existing app
  auth-adapter tests when present and relevant.
- SwiftUI widgets or UI customization: run the app build for the touched
  scheme; run UI/snapshot tests only when the app already has relevant tests.
- WKWebView/WebBridge changes: run the app build; manual WKWebView validation
  is still required.
- Migration changes: run a clean build of the migrated scheme if practical,
  because stale v3 imports/products can survive incremental builds.

Record unrelated build, lint, or test failures with the exact command, scheme,
destination, result, and failing owner. If checks cannot run, state why and
which OwnID behavior remains unverified.

## Reference-Backed Checks

Confirm only the reference-owned areas touched by the integration:

- Dependency and platform requirements match `install.md` for the selected
  surface.
- SDK initialization, configuration source, tenant/environment values, language,
  and logging match `configuration.md`.
- Namespace handles, context, and provider overrides match
  `namespace-handles.md`, `context.md`, and `providers.md` when those features
  are used.
- Passkey platform readiness matches `enable-passkeys.md` when the integration
  creates or authenticates passkeys.
- Provider callbacks hand off to the app's existing auth/session boundary.
- Third-party or tenant-owned setup is reported as external when it cannot be
  validated locally.
- Logging is appropriate for the environment and does not include passwords,
  OwnID access tokens, provider tokens, session payloads, raw backend
  responses, or personally identifying login IDs.
- Passkey behavior is exercised on an iOS 16+ device/simulator and account state
  that can create and retrieve passkeys when passkey behavior is in scope.

## Surface Checks

Run only checks for surfaces touched by the task. Use the approved
tenant/environment from the Integration Brief. Prefer UAT/test accounts for
manual flow validation when available; ask before using production credentials
or changing environment.

- Boost Flow: use `boost-flow.md` validation/checklist.
- Elite Flow: use `elite-flow.md` validation.
- Passkey Enrollment: use `passkey-enrollment.md` validation.
- WebBridge: use `webbridge.md` validation.
- UI Customization: use `ui-customization.md` validation and accessibility
  guardrails.
- Migration from v3: use `migration-v3-to-v4.md` validation guidance.

If multiple surfaces changed, validate each touched surface separately and
report which checks were skipped.

## External Validation Gaps

Report only required items for the touched integration that were not validated
locally:

- Tenant, console, passkey association, signing/provisioning, or hosted
  well-known file setup required by the selected surface.
- App backend/session/provider contracts required by the selected surface.
- Third-party identity-provider setup required by selected providers.
- Test account/device state needed for the changed flow.

## Handoff

Finish with:

- OwnID SDK version and iOS products used.
- Host app target/scheme/destination and files changed.
- Surfaces integrated or reviewed.
- Build/lint/test commands run, with results.
- Manual functional checks run, with account/environment used at a high level
  and without secrets.
- External setup verified versus still pending.
- Known risks, skipped checks, unrelated failures, and product/security
  questions that need the user or customer to answer.
