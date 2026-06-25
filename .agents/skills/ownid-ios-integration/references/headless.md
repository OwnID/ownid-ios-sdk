# Headless

Use this reference when an iOS app needs app-owned UI and orchestration for
OwnID SDK v4 discovery, passkey authentication, verification, login, passkey
creation, or signed-in passkey enrollment.

Full public docs: `../../../../docs/flows/headless.md`.

## Contents

- [Scope](#scope)
- [Before Editing](#before-editing)
- [Entry And Context Rules](#entry-and-context-rules)
- [State Machine](#state-machine)
- [Controllers And Errors](#controllers-and-errors)
- [Session Handoff](#session-handoff)
- [Validation](#validation)

## Scope

Headless exposes direct SDK entries instead of SDK-managed high-level auth
flows. The app owns screens, state machine, fallback order, session handoff,
navigation, analytics, and retry behavior. Passkey entries can still show
Apple platform passkey UI.

Use Headless only when the host app has a clear auth/session boundary and can
build UI for every operation it chooses to support.

## Before Editing

Read first:

- `install.md` and `configuration.md` for `OwnIDCore` and SDK initialization.
- `enable-passkeys.md` for AuthenticationServices, Associated Domains, and
  AASA setup.
- `context.md` and `namespace-handles.md` for login-ID/access-token context
  placement.
- `passkey-enrollment.md` when adding a signed-in "add passkey" action.

Identify before changing code:

- the login ID type collected by the app;
- the `@MainActor` state owner for the Headless sequence and active
  controllers;
- which returned `AuthRequirements` operations the app will support;
- the app fallback for unsupported, canceled, unavailable, or failed steps;
- where successful `LoginResponse.success` data enters the app session path;
- whether post-login passkey enrollment is required.

Stop and ask if the app has no approved path for a returned auth requirement or
if session handoff behavior is unclear.

## Entry And Context Rules

Use `OwnID.headless`.

- Use `auth.discover.start()` with a login ID supplied by per-attempt context or
  explicit params.
- Use `auth.login.start()` with an access token supplied by per-attempt context
  or explicit params after passkey or verification returns an `AccessToken`.
- Use `passkeys.auth` only when `.passkeyAuth` is returned in the current
  `AuthRequirements`.
- Use `verifications.email` or `verifications.phone` only for matching
  verification requirements.
- Use `passkeys.create` only when the app owns a backend continuation that
  expects `AttestationResponse`.
- Use `passkeys.enroll` for post-login "add passkey" UI with the current
  user's OwnID access token.

Prefer per-attempt context for values shared across multiple Headless steps.
Keep using the returned derived handle for the steps that belong to that attempt.
Use explicit params when a specific API call needs values from the current
requirement, such as a verification channel hint.

## State Machine

Implement one explicit state machine:

1. Collect the login ID in app UI.
2. Scope `OwnID.headless` with `.start(id, type: type)`.
3. Call `auth.discover.start()`.
4. Handle all `LoginResponse` cases: `.success`, `.authRequired`,
   `.accountNotFound`, and `.accountBlocked`.
5. For `.authRequired`, inspect `authRequirements.operations` and each
   operation's optional `channels`, then select only app-supported operations.
6. For `.passkeyAuth`, check `passkeys.auth.availability()`, start the
   operation, keep its controller, and continue with `auth.login` on success.
7. For `.emailVerification` or `.phoneNumberVerification`, start the matching
   verification API, keep its controller, and route an `.accessToken` result to
   `auth.login`.
8. Route `.proofToken` results only to an app path that explicitly expects a
   proof token.
9. After successful session handoff, optionally start `passkeys.enroll` from
   the current user's OwnID access token.

If no returned requirement can run in the app, continue through the app-owned
fallback.

## Controllers And Errors

- Keep operation and flow controllers strongly referenced while active, and
  await `whenSettled()` for terminal operation or flow results.
- Call `abort(reason:)` when the user leaves the step or the owner lifecycle
  ends while the controller is still active.
- Keep verification API controllers while complete/resend/cancel can still run.
  Call `cancel(reason:)` when abandoning the server challenge.
- `APIResult.canceled` means the surrounding Swift task was canceled before a
  direct API call completed.
- Treat availability messages and raw failure messages as diagnostics, not
  localized UI copy.

## Session Handoff

Route successful `LoginResponse` data through the app's own auth/session
boundary. Use `accessToken` and `sessionPayload` only according to the app
backend contract.

## Validation

Validate the smallest affected app surface:

- SDK initialization and iOS passkey setup are complete before Headless use.
- Login-ID and access-token context are scoped to the intended sequence.
- `discover` and `login` handle every `LoginResponse` case.
- Unsupported or unavailable requirements fall back through app-owned paths.
- Passkey auth, verification complete/resend/cancel, and optional enrollment
  preserve the app session model.
- Account switch or retry uses fresh scoped state and controllers.

Use the public docs for full examples and demo links.
