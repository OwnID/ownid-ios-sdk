# Context

Use this reference when an OwnID iOS SDK v4 integration needs OwnID runtime
context. Namespace-handle mechanics live in `namespace-handles.md`;
surface-specific references decide whether context is needed.

Source docs:

- `../../../../docs/setup/context.md`
- `../../../../docs/setup/access-token.md`
- `../../../../docs/setup/namespace-handles.md`

SDK contracts: `Context`, `Authz`, `LoginID`, `OwnID.withContext`,
`OwnID.setContext`, and `OwnID.clearContext`.

## Mental Model

Context is caller-supplied auth/display input attached to an SDK namespace handle.
Use it when the selected SDK surface reads runtime context instead of receiving
the same value through an explicit parameter.

Context can carry:

- `authz = .start(...)`: login-ID auth input.
- `authz = .fromToken(...)`: OwnID access-token auth input.
- `accountDisplayName`: optional display/context value.

A context has one `authz` slot. Choose either login ID or access token for the
next SDK call.

## Choosing Auth Input

- Use `.start(...)` when the selected surface starts from a visible login ID,
  such as email, phone, or another supported login identifier.
- Use `.fromToken(...)` when the selected surface continues work for an already
  identified or authenticated OwnID user using an OwnID access token.
- Use typed `LoginID` when the app already knows the login ID type. Raw strings
  are preserved as provided; validation and type resolution belong to the
  consuming SDK surface. Typed values may still be validated by that surface.
- Set `accountDisplayName` when the selected surface can use a display value.

## Scoped vs Top-Level Context

Prefer `withContext` for screen-like or request-like work:

```swift
let scopedFlows = OwnID.flows.withContext { context in
    context.authz = .start(email, type: .email)
}
```

Keep using the returned handle for the sequence. The child context is built
only from the block; unset fields do not inherit parent context values. If a
child needs both `authz` and `accountDisplayName`, set both in the same block.

Use `OwnID.setContext` only when subsequent calls through top-level `OwnID`
entry points should inherit shared context:

```swift
OwnID.setContext { context in
    context.authz = .fromToken(accessToken)
}
```

`OwnID.setContext` merges with the top-level context: assigned fields replace
current values, unassigned fields stay unchanged, and assigning `nil` clears
that field.

Call `OwnID.clearContext()` on sign-out, account switch, tenant switch, or any
boundary where later top-level calls must stop inheriting previous context.

Concrete `flows` and `webBridge` namespace handles expose
`withContext`, not in-place `setContext` or `clearContext`.

## Review Checks

- The selected surface reference explicitly supports runtime context.
- The integration chose one auth input: `.start(...)`, `.fromToken(...)`, or no
  `authz`.
- Context is attached near the concrete SDK call unless shared top-level context
  is intentional.
- Any shared top-level context is cleared or replaced on
  sign-out/account/tenant switch.
