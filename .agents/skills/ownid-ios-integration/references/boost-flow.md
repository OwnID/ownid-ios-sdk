# Boost Flow

Use this reference when adding OwnID SDK v4 Boost widgets to an existing native
iOS login or registration form. Boost keeps the form app-owned and returns
results through widget callbacks.

Full public docs: `../../../../docs/flows/boost-flow.md`.

## Contents

- [Mental Model](#mental-model)
- [Prerequisites](#prerequisites)
- [Widget Placement And Login ID](#widget-placement-and-login-id)
- [Login Widget Contract](#login-widget-contract)
- [Create-Passkey Widget Contract](#create-passkey-widget-contract)
- [State And Customization](#state-and-customization)
- [Integration Checklist](#integration-checklist)

## Mental Model

Boost enhances an existing native form. The app keeps its login and registration
screens, validation, submit buttons, password/manual paths, navigation,
registration endpoint, and session model.

OwnID supplies two widgets:

- `OwnIDLoginWidget` starts Boost login and calls `onLogin` after successful
  authentication.
- `OwnIDCreatePasskeyWidget` starts Boost create-passkey from a registration
  form. It can return `onNewPasskey` for registration submit or `onLogin` when
  the user is recognized and authenticated.

## Prerequisites

- Add `OwnIDSwiftUI` for Boost widgets.
- Initialize OwnID before rendering widgets.
- Complete iOS passkey prerequisites.
- Keep password login and manual registration paths available next to Boost.
- Configure `sessionCreate` when Boost login should return an app-defined
  session value as `response.session`.

## Widget Placement And Login ID

Place the widget in the same native form the user already edits:

- Login screen: `OwnIDLoginWidget(onLogin: ..., loginID: loginID)`.
- Registration/create-account screen:
  `OwnIDCreatePasskeyWidget(..., loginID: loginID)`.

Recommended layout: put the widget in the password row, usually before the
password input or password action. Keep the app's submit buttons available.

The built-in widgets trim whitespace and newlines from `loginID`. Blank values
are passed as no login ID. For forms with a visible login ID field, pass that
field directly to the widget.

After success, treat `response.loginID.id` as authoritative and copy it back
into the form because the SDK may resolve or normalize the value.

Boost is token-first. If the current SDK context contains an OwnID access token,
the SDK derives the login ID from that token and starts the token login path for
that run. Widget login ID hints do not override that token path.

Without an access token, Boost uses login ID hints in this order:

1. Login ID supplied to the widget after trimming.
2. Login ID or raw login ID from the current SDK context.
3. Stored last user.
4. SDK login-ID collection UI, when the flow still needs an identifier.

Keep signed-in access-token context off public login/register screens unless
token-first behavior is intentional.

## Login Widget Contract

Use `OwnIDLoginWidget` on the existing sign-in form:

```swift
OwnIDLoginWidget(
    onLogin: { response in
        email = response.loginID.id
        finishLogin(response)
    },
    loginID: email,
    onError: { failure in
        showRetryableOwnIDError(failure)
    },
    onCancel: { reason in
        // Stay on the login screen.
    }
)
```

`onLogin` receives `BoostFlowLoginResponse`:

- `loginID`: authenticated login identifier. Update the visible form value.
- `authMethod`: completed method, such as passkey, OTP, or FaceKey.
- `accessToken`: OwnID access token for the authenticated user.
- `sessionPayload`: server-provided payload for app session integration.
  Structured values remain JSON text; plain strings remain strings.
- `session`: app-defined value returned by `sessionCreate`; `nil` when the
  provider is not configured or unavailable for that login.

Session handoff:

- Boost always includes `accessToken` and `sessionPayload` in successful login
  responses.
- When `sessionCreate` is configured and available, the SDK passes `loginID`,
  `authMethod`, `accessToken`, and `sessionPayload` to the provider before
  `onLogin`; the provider result becomes `response.session`.
- Without an available `sessionCreate`, `onLogin` receives `accessToken` and
  `sessionPayload` directly and `response.session` is `nil`.

`onCancel` means the user or flow canceled before success. Keep the current
screen state and leave password login enabled.

`onError` covers flow start failures and terminal failures. Show retryable app
copy, log diagnostics according to the app's policy, and keep password login
available. Provider failures such as `sessionCreate` failures surface as
integration failures to the flow.

Before `onLogin`, the SDK may satisfy server requirements with passkey,
verification, or another supported Boost operation.

## Create-Passkey Widget Contract

Use `OwnIDCreatePasskeyWidget` on registration or create-account screens. It can
finish in two ways:

- `onNewPasskey`: a create-passkey result is ready for a pending registration.
- `onLogin`: the user was recognized and authenticated instead of creating a new
  account; handle it exactly like Boost login.

Minimal state pattern:

```swift
@State private var createPasskeyResponse: BoostFlowCreatePasskeyResponse?

private var ownIdDataForSubmit: String? {
    guard let response = createPasskeyResponse, email == response.loginID.id else {
        return nil
    }
    return response.ownIdData
}

OwnIDCreatePasskeyWidget(
    onLogin: { response in
        email = response.loginID.id
        createPasskeyResponse = nil
        finishLogin(response)
    },
    onNewPasskey: { response in
        email = response.loginID.id
        createPasskeyResponse = response
    },
    onReset: {
        createPasskeyResponse = nil
    },
    loginID: email,
    onError: { failure in
        showRetryableOwnIDError(failure)
    },
    onCancel: { reason in
        // Stay on the registration screen.
    }
)
```

Submit `ownIdDataForSubmit` unchanged with the app's registration request,
according to the backend contract.

`BoostFlowCreatePasskeyResponse` contains:

- `loginID`: registered user's login identifier. Copy it back to the form.
- `proofToken`: proof of completed registration operations when returned; can
  be `nil`.
- `ownIdData`: opaque value for the app registration backend; can be `nil`.

If `ownIdData` is `nil`, keep the manual registration/password path available.

Never submit stale `ownIdData`. If the user changes the form login ID after
`onNewPasskey`, clear the stored response or ignore it until the current form
login ID again equals `response.loginID.id`.

## State And Customization

`OwnIDCreatePasskeyWidget` can show a completion checkmark after
`onNewPasskey`. `onReset` means the widget cleared that completed state; clear
the app's pending response too.

The public widget view model keeps only the latest create-passkey result in
memory while that view model is alive. If the user returns to the matching login
ID, the view model can re-emit `onNewPasskey` and show the checkmark again.
Before registration submit, use `ownIdData` only when the current form login ID
matches `response.loginID.id`.

After a successful registration submit, clear the pending create-passkey
response. If registration fails, follow the app's retry policy, but never submit
the response for a different login ID.

In repeated/dynamic UI, use stable SwiftUI identity. When state must survive
navigation, row recycling, conditional view replacement, or custom widget
composition, keep one externally owned view model per logical widget.

Prefer the built-in widgets. Customize through public parameters only:

- `theme: OwnIDTheme` for per-widget theme snapshots.
- `widgetStrings: BoostWidgetStrings` for widget copy.
- `showSpinner: false` when the screen already shows progress.
- `.iconButton`, `.checkmark`, and `.orText` for component-level changes.
- `OwnIDLoginWidgetViewModel` or `OwnIDCreatePasskeyWidgetViewModel` when the
  screen must own widget state across navigation/custom UI.
- `OwnIDBoostButton` only when the app fully owns flow start and state mapping
  but wants the shared Boost row layout.

## Integration Checklist

- `OwnIDSwiftUI` is present for Boost widgets.
- OwnID initializes before widget rendering.
- iOS passkey setup is complete.
- Login widget receives the visible form login ID, updates the form from
  `response.loginID.id`, and keeps password login available on cancel/error.
- Login success uses `response.session` when present, otherwise uses
  `response.accessToken` and `response.sessionPayload` through the app's session
  handoff.
- Create-passkey widget stores only the latest matching response, submits
  current `ownIdData` unchanged, and clears it on `onReset` and successful
  registration.
- `onLogin` from the create-passkey widget routes through the login path.
- Repeated/dynamic widgets have stable SwiftUI identity or separate externally
  owned view models.
- Success, cancel, and error callbacks have been exercised with the host app's
  session, password login, and registration paths.
