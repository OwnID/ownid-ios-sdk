# OwnID Access Token

An OwnID Access Token is a signed JWT that proves successful OwnID authentication. After authentication, the app owns this sensitive value and uses it at the app session boundary or for OwnID operations that require an authenticated user.

## Receiving and Using the Token

An authentication result or callback can provide an [`AccessToken`](../../OwnIDCore/Sources/Models/Tokens.swift). The selected flow guide describes when the token is returned and the exact response shape.

Common uses include:

- Passing the token to [`sessionCreate`](providers.md#session-create), together with the session payload, to create or restore the app session.
- Passing the current user's token to authenticated OwnID operations, such as [Passkey Enrollment](../flows/passkey-enrollment.md).
- Providing the token as [OwnID Context](context.md) when related SDK calls should share the same authenticated-user input.

## Lifecycle and Storage

Keep the token for the part of the app session that needs authenticated OwnID operations:

- For an immediate session handoff or SDK operation, keep the token in memory until that work completes.
- For later operations during the active app session, keep it in session-scoped state associated with the current account and tenant.
- When access must survive an app restart, store the token in [Keychain](https://developer.apple.com/documentation/security/keychain-services).
- When successful authentication returns a new token, update the value associated with that app session.

Clear the app-owned token together with the related app session on sign-out, account change, or tenant change. When the session requires reauthentication, complete a supported authentication flow to receive a current token.

## Providing the Token to OwnID

Use scoped context when a single flow or sequence needs the token:

```swift
let ownID = OwnID.withContext { context in
    context.authz = .fromToken(accessToken)
}
```

Use `OwnID.setContext` when subsequent top-level OwnID calls should share the token. If top-level context was set, call `OwnID.clearContext()` when clearing the related app session. See [Context](context.md) for scope and namespace-handle behavior.

## Security Practices

- Expose the token only to app components and backend endpoints that perform the authenticated handoff or OwnID operation.
- Use `AccessToken.description` when a diagnostic representation is needed; it returns a shortened token value.
- Pass the token unchanged through public OwnID APIs and the app's authenticated transport.
- Keep storage and cleanup aligned with the app's existing session-security policy.
