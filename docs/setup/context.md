# Context

OwnID context lets you attach a login ID, Access Token, or account display name to an SDK namespace handle. Use it when a flow, operation, or API run should read those values from the namespace handle instead of receiving them as explicit parameters.

For how context attaches to namespace handles, see [Namespace Handles](namespace-handles.md).

## Context Values

Context can carry:

- `authz = .start(...)`: login-ID auth input.
- `authz = .fromToken(...)`: Access Token auth input.
- `accountDisplayName`: optional display/context value.

A [`Context`](../../OwnIDCore/Sources/Models/Context.swift) has one `authz` slot, so choose either login ID or Access Token for the next SDK call. Raw login IDs are stored as provided and may be resolved or validated by the consuming SDK feature. Typed [`LoginID`](../../OwnIDCore/Sources/Models/LoginID.swift) values are preserved as provided and may still be validated by that feature.

Only a few SDK surfaces read `accountDisplayName`. The direct passkey attestation API uses it as the fallback for `PasskeyAttestationAPIParams.accountDisplayName`; WebBridge exposes it in the context payload for hosted pages that request context.

## Scoped Context

Use `withContext` when one flow, operation, or API run needs its own auth input. It returns a derived namespace handle and does not mutate the current handle.

```swift
let headless = OwnID.headless.withContext { context in
    context.authz = .start(email, type: .email)
}

let response = await headless.auth.discover.start()
```

The returned handle stays bound to that context. Keep using it for the related sequence instead of switching back to the original handle midway.

The child context is built only from the `withContext` block. Unset context fields do not inherit values from a previously set parent context. If a child needs both `authz` and `accountDisplayName`, set both in the same block.

## Current Context

Use `setContext` only when future calls from the current handle should reuse the same context.

```swift
OwnID.setContext { context in
    context.authz = .fromToken(accessToken)
}
```

`setContext` updates the current handle in place:

- Fields assigned in the block replace existing values.
- Fields not assigned keep their current values.
- Assigning `nil` clears that field.

Use `clearContext` when the user signs out, switches account, switches tenant, or the app no longer wants calls from that handle to inherit the previous context.

```swift
OwnID.clearContext()
```

For login screens, one-off actions, and WebBridge instances, prefer `withContext` unless shared current context is intentional.
