# Elite Flow

Use this reference when integrating OwnID SDK v4 Elite Flow into an iOS app.

Full public docs: `../../../../docs/flows/elite-flow.md`.

Read first:

- `install.md` and `configuration.md` for `OwnIDCore` and SDK initialization.
- `providers.md` for `sessionCreate`, `passwordAuthenticate`, Google, and Sign
  in with Apple setup.
- `context.md` and `namespace-handles.md` for context/provider placement.

## Contents

- [Scope](#scope)
- [Before Editing](#before-editing)
- [Providers And Context](#providers-and-context)
- [Event Rules](#event-rules)
- [Controller And Result Rules](#controller-and-result-rules)
- [Options](#options)
- [Implementation Pattern](#implementation-pattern)
- [Validation](#validation)

## Scope

Elite Flow opens a temporary SDK-managed `WKWebView` with an OwnID-hosted page.
Inside that page, the OwnID Web SDK runs the hosted authentication experience;
the native iOS SDK uses OwnID WebBridge plumbing to deliver hosted-page events
to `EliteFlowContext.events`.

Use Elite when OwnID owns the primary hosted auth UI and the app owns only the
entry point, provider setup, native registration/session handoff, lifecycle, and
fallback UI.

## Before Editing

- `OwnIDCore` is installed and OwnID is initialized before `start`.
- iOS passkey setup from the public README is complete.
- The tenant/hosted page requirements are known: native registration handoff,
  session creation, password auth, Google or Apple sign-in, passkeys, and
  runtime context.
- App behavior is decided for `onNativeAction`, `onFinish`, `onError`, and
  `onClose`.

## Providers And Context

Register app-wide providers high in the SDK tree with `OwnID.setProviders`.
Use `OwnID.flows.withProviders` only when one Elite run must override app-wide
provider behavior.

If the hosted page needs a login ID, OwnID access token, or account display
name, apply `withContext` on `OwnID.flows` before `elite.start(...)`, then call
`start` on the returned derived handle. Prefer one-run context for public login
or registration entry points.

Sign in with Apple is available through `OwnIDCore` when the app capability,
entitlements/provisioning, presentation context, and OwnID tenant setup are in
place. It is not registered through `OwnID.setProviders`.

`EliteFlowContext` is separate from SDK runtime context. It configures the one
Elite WebView run through `events` and optional `options`.

## Event Rules

Configure hosted-page callbacks with `EliteFlowContext.events`. Handlers run on
the main actor. After a terminal handler returns, the SDK closes the WebView and
settles the controller.

| Event | App responsibility |
| --- | --- |
| `onNativeAction(loginID, ownIdData, accessToken)` | Continue native handoff, commonly registration. Preserve `ownIdData` unchanged and treat `accessToken` as optional app/backend handoff data. |
| `onFinish(loginID, authMethod, accessToken)` | Route hosted authentication completion through the app auth/session boundary. |
| `onError(error)` | Handle a hosted functional error with retry/fallback UI. |
| `onClose()` | Clear transient state after a normal hosted close. |

If `onFinish`, `onError`, or `onClose` are omitted, the SDK installs default
hosted-page handlers. Add handlers when the app must update auth state,
navigation, analytics, or user-visible fallback UI. `onNativeAction` has no
default app behavior.

## Controller And Result Rules

Starting Elite returns an app-owned controller. Keep it strongly referenced
until `whenSettled()` completes, disable duplicate starts while active, and call
`abort(reason:)` when the owning lifecycle ends.

Interpret `whenSettled()` as infrastructure settlement:

- `.success`: a terminal hosted-page handler completed. Functional
  auth/registration work was handled in the callback; no auth payload is
  returned from `whenSettled()`.
- `.canceled`: the app or SDK canceled before a terminal hosted event.
- `.failure`: SDK or WebBridge infrastructure failed before a terminal hosted
  event.

## Options

Hosted page UX and business behavior come from the OwnID-hosted Web SDK page and
tenant/server configuration. `EliteFlowContext.options` only configures the
SDK-managed WebView operation. On iOS, the options closure receives an
`EliteFlowOptionsBuilder`.

For normal public customization, use:

- `backgroundColor`

Leave options unset unless the app needs SDK-managed WebView container and
safe-area background customization. Check public API comments before using
advanced WebView content options.

## Implementation Pattern

```swift
let flowContext = EliteFlowContext { builder in
    builder.events { events in
        events.onNativeAction { loginID, ownIdData, accessToken in
            pendingRegistration = PendingRegistration(
                email: loginID,
                ownIdData: ownIdData
            )
        }

        events.onFinish { loginID, authMethod, accessToken in
            // Route through the app auth/session boundary.
        }

        events.onError { error in showEliteFallback(error) }
        events.onClose { clearEliteRunningState() }
    }
}

eliteController = OwnID.flows.elite.start(flowContext)
```

If the run needs scoped context or an intentional provider override, start from
the scoped namespace returned by `withContext` or `withProviders`. Clear the
stored controller after `whenSettled()` returns.

## Validation

When validation is in scope, exercise the Elite entry point and confirm startup
prerequisites, required providers/context, native `ownIdData` handoff, session
handoff, hosted error/close handling, controller retention, and cancellation or
failure fallback.
