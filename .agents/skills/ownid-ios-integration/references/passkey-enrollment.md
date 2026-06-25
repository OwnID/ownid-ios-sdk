# Passkey Enrollment

Use this reference when an iOS host app adds a passkey for the current
signed-in user with OwnID SDK v4.

Full public docs: `../../../../docs/flows/passkey-enrollment.md`.

## Contents

- [Scope](#scope)
- [Before Editing](#before-editing)
- [Implementation Pattern](#implementation-pattern)
- [Proof-Token Path](#proof-token-path)
- [Lifecycle And Results](#lifecycle-and-results)
- [Validation](#validation)

## Scope

Passkey Enrollment is a signed-in account flow. The app must already have a
valid OwnID `AccessToken` for the current user. Use it from account security,
post-login, or registration-completion UI after that token exists.

## Before Editing

Identify:

- where the current user's OwnID `AccessToken` comes from;
- the account UI action that starts enrollment;
- the `@MainActor` view model or coordinator that will own async work and the
  controller;
- whether the account area already uses OwnID current context;
- the fallback UX for unavailable, canceled, or failed enrollment;
- whether iOS passkey prerequisites are complete.

If there is no OwnID `AccessToken`, stop and ask how the app should obtain one
before adding enrollment.

## Implementation Pattern

Use `OwnID.headless.passkeys.enroll`.

Prefer a derived handle for a single "Add passkey" action:

```swift
let passkeyEnroll = OwnID.headless
    .withContext { context in
        context.authz = .fromToken(accessToken)
    }
    .passkeys.enroll
```

Check availability and start from the same derived handle:

```swift
var isAvailable = false
await passkeyEnroll.availability()
    .onAvailable { isAvailable = true }
    .onUnavailable { message in
        // Hide or disable the action; log message for integration diagnostics.
    }

guard isAvailable else { return }

let controller = passkeyEnroll.start()
```

Passing `PasskeyEnrollFlowContext.accessToken` directly is also valid. Use the
same token/context values for `availability(...)` and `start(...)`.

Lower-level enroll APIs also require an Access Token from explicit params or
the current OwnID context. Without one, the SDK returns the typed bad-request
failure before sending the enrollment request.

Use current OwnID context only when the account area already owns intentional
current-user OwnID state. Keep that context aligned with the current signed-in
account.

## Proof-Token Path

Set `PasskeyEnrollFlowContext.proofToken` only when a previous OwnID step
returned a proof token valid for passkey enrollment.
Without `proofToken`, the flow creates a local passkey first and
AuthenticationServices UI can appear.

For lower-level integrations that already manage passkey attestation and only
need to enroll a proof token, follow the public guide instead of the normal
add-passkey flow.

## Lifecycle And Results

Store the controller strongly while the flow is active, normally in the view
model or coordinator that owns the account action. Disable the enrollment
action while running, await `controller.whenSettled()`, and call
`controller.abort(reason:)` if the owner is torn down before settlement.

Treat the returned controller as one enrollment attempt. Do not start another
attempt while that controller is active. For retry after settlement, clear the
stored controller and start a new attempt from the current entry or a fresh
scope with current token/context.

Success means enrollment completed for `response.loginID`. Cancellation or
failure means enrollment did not complete; keep the current app session intact
and show app-owned retry or fallback UI if needed.

## Validation

Validate on a device or simulator configuration that can use passkeys:

- availability gates the signed-in account action;
- start opens expected platform passkey UI unless using a valid `proofToken`;
- success updates or refreshes account/security state for `response.loginID`;
- cancel and failure keep the user signed in and allow retry;
- account switch or retry uses the current user's token/context.

Use the public docs for full examples, direct API/operation surfaces, and demo
links. Use Enable Passkeys for iOS platform setup and relying-party domain
checks.
