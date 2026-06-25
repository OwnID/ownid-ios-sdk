# Namespace Handles

OwnID namespaces expose handles for SDK flows, operations, API runs, and WebBridge sessions. Context values and provider bindings can be attached to namespace handles.

- [Context](context.md) is caller-supplied auth/display input, such as a login ID, OwnID Access Token, or account display name.
- [Providers](providers.md) are app-owned capabilities, such as session creation, password authentication, or social sign-in.

## Namespace Model

After initialization, use top-level `OwnID` entry points to access SDK namespace handles.

A handle returned by `withContext` or `withProviders` keeps the context and provider bindings that were attached to it. Keep using the returned handle for the sequence it starts.

After destroying or reinitializing the same SDK instance, reacquire namespace handles from `OwnID` before starting more work.

## How to Place Context and Providers

Attach context as close as possible to the concrete flow, operation, API run, or WebBridge session that needs it.

Register providers on the shared or top-level namespace handle unless one SDK request or session needs an override. Use `withProviders { ... }` only for that override case.

Build the derived handle before checking availability, running preflight, starting, or creating the SDK feature.

## Derived Handles

Use derived handles for one concrete flow, operation, API run, or WebBridge session:

- `withContext { ... }` returns a derived handle with a new context snapshot.
- `withProviders { ... }` returns a derived handle with provider overrides.

Derived handles keep the rest of their parent handle's bindings, with these scope rules:

- `withContext { ... }` builds a new context only from that block. Values you do not set in the block are not set on the derived handle, even if the parent handle has them.
- `withProviders { ... }` inherits existing provider bindings and replaces only the provider types registered in that block.
- If `withProviders { ... }` registers no providers, the current handle is returned unchanged.

```swift
let bridge = OwnID.webBridge
    .withContext { context in
        context.authz = .fromToken(accessToken)
    }
    .withProviders { providers in
        providers.sessionCreate { provider in
            provider.create { params in await checkoutSessionCreate(params) }
        }
    }
    .create()
```

## Current Instance Updates

Use current instance updates only when future calls from that SDK instance should inherit the change:

- `setContext { ... }` updates context on the current SDK instance.
- `clearContext()` clears context from the current SDK instance.
- `setProviders { ... }` updates provider bindings on the current SDK instance.

Set shared context when future calls should reuse it; clear it when that shared context should stop applying:

```swift
OwnID.setContext { context in
    context.authz = .fromToken(accessToken)
}

OwnID.clearContext()
```

`setContext` merge semantics:

- Fields assigned in the block replace existing values.
- Fields not assigned keep their current values.
- Assigning `nil` clears that field.

`setProviders` replaces provider bindings of the types registered in the block.
Existing bindings for provider types not declared in the block remain unchanged.
