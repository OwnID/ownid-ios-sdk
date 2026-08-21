# Boost Flow

Boost Flow adds OwnID to an existing native login or account-creation form. The user stays in your app UI, taps an OwnID widget, and the SDK runs the recommended authentication or create-passkey path for that entry point.

Use Boost when the app keeps its current password login or registration form and adds OwnID as the passkey-first path next to it.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../images/ios-boost-login-dark.png">
  <source media="(prefers-color-scheme: light)" srcset="../images/ios-boost-login-light.png">
  <img src="../images/ios-boost-login-light.png" width="420" alt="iOS Boost login widget">
</picture>

## Contents

- [Minimal Integration](#minimal-integration)
- [Examples](#examples)
- [Prerequisites](#prerequisites)
- [Flow Shape](#flow-shape)
- [Integration Details](#integration-details)
- [Widget Callbacks](#widget-callbacks)
- [Customization](#customization)
- [Security and Data Handling](#security-and-data-handling)

## Minimal Integration

### Login Widget Integration

Add [`OwnIDLoginWidget`](../../OwnIDSwiftUI/Sources/Widget/OwnIDLoginWidget.swift) next to the app's password field. Pass the same login ID value that the user edits in the form, then handle `onLogin`, `onError`, and `onCancel`.

```swift
import OwnIDCore
import OwnIDSwiftUI
import SwiftUI

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""

    let onPasswordLogin: (String, String) -> Void
    let onOwnIDLogin: (BoostFlowLoginResponse) -> Void

    var body: some View {
        VStack(spacing: 12) {
            TextField("Email", text: $email)

            HStack(spacing: 8) {
                OwnIDLoginWidget(
                    onLogin: { response in
                        email = response.loginID.id
                        onOwnIDLogin(response)
                    },
                    loginID: email,
                    onError: { error in
                        // Show an app-owned error or fallback state and keep password login available.
                    },
                    onCancel: { reason in
                        // Keep the user on the login screen.
                    }
                )

                SecureField("Password", text: $password)
            }

            Button("Login") {
                onPasswordLogin(email, password)
            }
        }
    }
}
```

### Create-Passkey Widget Integration

Add [`OwnIDCreatePasskeyWidget`](../../OwnIDSwiftUI/Sources/Widget/OwnIDCreatePasskeyWidget.swift) to the registration form. Store the create-passkey response for registration submission.

```swift
import OwnIDCore
import OwnIDSwiftUI
import SwiftUI

struct RegisterView: View {
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var createPasskeyResponse: BoostFlowCreatePasskeyResponse?

    let registerUser: (String, String, String, String?) -> Void
    let onOwnIDLogin: (BoostFlowLoginResponse) -> Void

    private var ownIdData: String? {
        createPasskeyResponse?.ownIdData(forLoginID: email)
    }

    var body: some View {
        VStack(spacing: 12) {
            TextField("Name", text: $name)
            TextField("Email", text: $email)

            HStack(spacing: 8) {
                OwnIDCreatePasskeyWidget(
                    onLogin: { response in
                        email = response.loginID.id
                        onOwnIDLogin(response)
                    },
                    onNewPasskey: { response in
                        email = response.loginID.id
                        // Keep this response for submit. Read ownIdData with the current form login ID.
                        createPasskeyResponse = response
                    },
                    onReset: {
                        // The widget cleared its completed create-passkey state, for example after the form login ID
                        // no longer matches the saved response. Discard saved create-passkey data.
                        createPasskeyResponse = nil
                    },
                    loginID: email,
                    onError: { error in
                        // Show an app-owned error or fallback state and keep manual registration available.
                    },
                    onCancel: { reason in
                        // Keep the current account-creation UI state.
                    }
                )

                SecureField("Password", text: $password)
            }

            Button("Submit") {
                registerUser(name, email, password, ownIdData)
            }
        }
    }
}
```

## Examples

- [Base login widget](../../Demo/DemoBase/App/Views/Boost/BoostLoginTab.swift)
- [Base create-passkey widget](../../Demo/DemoBase/App/Views/Boost/BoostCreatePasskeyTab.swift)
- [Advanced login widget example](../../Demo/DemoAdvanced/App/Views/Flows/Boost/BoostLoginScreen.swift)
- [Advanced create-passkey widget example](../../Demo/DemoAdvanced/App/Views/Flows/Boost/BoostCreatePasskeyScreen.swift)

## Prerequisites

- Add the SwiftUI SDK as described in [Install](../../README.md#install), initialize OwnID in [Configuration](../setup/configuration.md), and complete platform passkey setup in [Passkey Setup](../setup/passkeys.md).
- Register [`sessionCreate`](../setup/providers.md#session-create) if Boost login should return an app-defined session as `response.session`. Without an available provider, `onLogin` still receives `accessToken` and `sessionPayload`.
- Keep the existing password login available next to the OwnID widget. Keep manual registration as the fallback when no matching `ownIdData` is available.

## Flow Shape

### Login Flow Shape

```mermaid
flowchart LR
    A["User enters login ID<br/>(optional)"] --> B["User taps Login widget"]
    B --> C["SDK runs Boost Login"]
    C --> D{"Result"}
    D -->|"onLogin"| E["App creates or<br/>restores session"]
    D -->|"onError"| F["App shows error or<br/>fallback state"]
    D -->|"onCancel"| G["App keeps current<br/>screen state"]
```

### Create-Passkey Flow Shape

```mermaid
flowchart LR
    A["User enters login ID<br/>(optional)"] --> B["User taps<br/>Create Passkey widget"]
    B --> C["SDK runs Create Passkey"]
    C --> D{"Result"}
    D -->|"onLogin"| E["App creates or<br/>restores session"]
    D -->|"onNewPasskey"| F["App keeps response<br/>for registration"]
    D -->|"onError or onCancel"| H["App keeps current<br/>screen state"]
```

## Integration Details

Use these rules when wiring app state to Boost callbacks:

- **Login ID input:** Pass the same email, phone, or username value that the user edits in your form. The widget ignores blank values.
- **Returned login ID:** When `onLogin` or `onNewPasskey` returns, update the form from the response login ID. OwnID may normalize or resolve the value during the flow.
- **Password fallback:** Keep the app's password login available. For registration, use the normal manual path when the user cancels, OwnID cannot complete, or no matching `ownIdData` is available.
- **Create-passkey data:** Store the create-passkey response for registration submit. Read `ownIdData` with `ownIdData(forLoginID:)` so it is used only for the current form value. When it returns non-nil `ownIdData`, do not ask for, validate, or require a user-entered password. Submit `ownIdData` unchanged with the registration request. Whether the identity system creates a passwordless account, generates an internal password, or uses another supported mechanism is determined by the app's backend business logic.
- **Changed form value:** If the user changes the email, phone, or username after `onNewPasskey`, clear the stored create-passkey response or ignore it until the login ID matches again. The widget calls `onReset` when it clears completed create-passkey state, including after the form login ID stops matching the saved response.
- **No-proof result:** `onNewPasskey` can return without `ownIdData` when passkey creation is unavailable or fails. Continue with normal registration and do not submit OwnID proof data.

## Widget Callbacks

### Login Widget

- `onLogin`: Called when Boost login completes successfully. It receives [`BoostFlowLoginResponse`](../../OwnIDCore/Sources/Flow/Boost/BoostFlow.swift) with these fields:

  - `loginID`: Update the visible form value if the SDK resolved or normalized the login ID.
  - `authMethod`: Record or branch on the completed authentication method, such as passkey or OTP, when the app needs it.
  - `accessToken`: [OwnID Access Token](../setup/access-token.md) for app session handoff when needed.
  - `sessionPayload`: Server-provided payload for app session integration; also passed to [`sessionCreate`](../setup/providers.md#session-create) when that provider is available.
  - `session`: App-defined value returned by [`sessionCreate`](../setup/providers.md#session-create); `nil` when the provider is not configured or unavailable.

- `onError`: Called when Boost login fails. It receives [`BoostLoginFlowFailure`](../../OwnIDCore/Sources/Flow/Boost/BoostFlow.swift); branch on the concrete failure type for routing decisions, show app-owned retry or fallback UI, and keep password login available.
- `onCancel`: Called when the user closed the flow or the flow was canceled. It receives a `Reason`; keep the user on the same screen unless the app has a better fallback for that reason.

### Create-Passkey Widget

- `onLogin`: Called when OwnID recognizes and authenticates an existing user instead of creating a new account. It receives `BoostFlowLoginResponse`; see [Login Widget](#login-widget) for response fields.

The create-passkey widget can also complete successfully with a create-passkey response:

- `onNewPasskey`: Called when the widget has a create-passkey response for the current form value. It receives [`BoostFlowCreatePasskeyResponse`](../../OwnIDCore/Sources/Flow/Boost/BoostFlow.swift) with these fields:

  - `loginID`: Update the registration form and validate it before submit.
  - `proofToken`: Proof Token produced by passkey-related operations, or `nil` when no proof is available.
  - `ownIdData`: Submit with the registration request when `ownIdData(forLoginID:)` returns it. Do not modify it.

- `onReset`: Called when the widget clears its completed create-passkey state, including after the form login ID stops matching the saved response. Clear the stored create-passkey response.
- `onError`: Called when the create-passkey flow fails. It receives [`BoostCreatePasskeyFlowFailure`](../../OwnIDCore/Sources/Flow/Boost/BoostFlow.swift); branch on the concrete failure type for routing decisions, show app-owned retry or fallback UI, and keep manual registration available.
- `onCancel`: Called when the user closed the flow or the flow was canceled. It receives a `Reason`; keep the user on the same screen unless the app has a better fallback for that reason.

### Common Failures

| Failure | What it usually means | Recommended handling |
| --- | --- | --- |
| `input(.unresolvedLoginID)` | Boost could not resolve a usable login ID from the form value, current context, or Access Token. | Let the user enter or correct the identifier and start a new Boost attempt. If the flow used an Access Token or context value, check that the supplied data contains a valid login ID. |
| `account(.blocked)` | The resolved account is blocked and cannot continue through this OwnID path. | Route the user to the app's blocked-account, recovery, or support path. Treat this as an expected account-state result, not as a retryable SDK failure. |
| `account(.notFound)` | This path expected an existing account, but none was found for the resolved login ID. | Route according to the screen: registration, another identifier entry path, or the app's normal account-not-found handling. Treat this as an expected account-state result. |
| `insufficientAuth` | Boost could not complete authentication with the available operations. | Offer another app-level sign-in or registration path, or let the user start a new attempt later. If the login uses `allowedAuthOperations`, check that it allows the authentication categories intended for this entry point. |
| `operationFailed` | A required SDK operation could not start, was unavailable, or failed while the flow was running. | End the current attempt and offer retry or another app-level path. Use `operationType`, nested `operationFailure`, and diagnostics to understand which SDK operation failed. |
| `sessionCreationFailed` | OwnID authentication completed, but the app's `sessionCreate` provider failed. | Show an app session/sign-in failure state and inspect the [`sessionCreate`](../setup/providers.md#session-create) provider. Do not treat this as failed OwnID authentication. |
| `unexpected` | The flow hit an unexpected SDK, runtime, or integration state. | Show a generic failure or retry state. Log diagnostics and retry only by starting a new Boost attempt. |

Use the failure's `errorCode` as a localization key when showing OwnID-related copy. Treat `message` and nested errors as diagnostics, not end-user text.

## Customization

### Customize the Default Widgets

The default widgets support theme, strings, showing OwnID before or after the `or` separator, icon button, checkmark, spinner, and separator text customization.

- For theme and palette setup, see [Themes and Colors](../customization/themes-and-colors.md).
- For SDK language setup, see [Configuration](../setup/configuration.md#language).
- For widget copy, see [Localization](../customization/localization.md).
- For deeper widget customization, see [Boost Widget Customization](../customization/boost-widgets.md).

### Use Your Own UI

If the standard widgets do not fit your UI, render your own button or control and start Boost from an app-owned `@MainActor` `ObservableObject` or coordinator.

The owner creates a `BoostFlowContext`, starts the corresponding flow, keeps the returned controller strongly referenced, and awaits `whenSettled()`. While the flow is active, use app-owned state to show progress and prevent duplicate starts. If the owner is torn down before settlement, abort the active controller with an appropriate `Reason`.

#### Login

```swift
@ObservedObject var boostLogin: BoostLoginViewModel

Button(boostLogin.isRunning ? "Running…" : "Continue with OwnID") {
    boostLogin.start(email: email)
}
.disabled(email.isEmpty || boostLogin.isRunning)
```

The owner starts and observes the flow:

```swift
import Combine
import Foundation
import OwnIDCore

@MainActor
final class BoostLoginViewModel: ObservableObject {
    @Published private(set) var isRunning = false

    private var controller: (any BoostLoginFlowController)?

    deinit {
        controller?.abort(reason: .userClose(details: "Boost login owner deinitialized"))
    }

    func start(email: String) {
        guard !isRunning else { return }
        isRunning = true

        let context = BoostFlowContext {
            $0.loginID(email, type: .email)
        }
        let controller = OwnID.flows.boost.login.start(context)
        self.controller = controller

        Task { @MainActor [weak self] in
            let result = await controller.whenSettled()
            guard let self else { return }

            self.controller = nil
            self.isRunning = false
            result
                .onSuccess { response in
                    // Use response to update the app session, then publish the next UI state or effect.
                }
                .onCanceled { reason in
                    // Use reason to publish the app state appropriate for cancellation.
                }
                .onError { failure in
                    // Use failure to publish app-owned error or fallback state.
                }
        }
    }
}
```

#### Create Passkey

```swift
@ObservedObject var boostCreatePasskey: BoostCreatePasskeyViewModel

Button(boostCreatePasskey.isRunning ? "Running…" : "Create a passkey") {
    boostCreatePasskey.start(email: email)
}
.disabled(email.isEmpty || boostCreatePasskey.isRunning)
```

The create-passkey flow uses the same controller ownership pattern. Its owner handles both possible success values:

```swift
@MainActor
final class BoostCreatePasskeyViewModel: ObservableObject {
    @Published private(set) var isRunning = false

    private var controller: (any BoostCreatePasskeyFlowController)?

    deinit {
        controller?.abort(reason: .userClose(details: "Boost create-passkey owner deinitialized"))
    }

    func start(email: String) {
        guard !isRunning else { return }
        isRunning = true

        let context = BoostFlowContext {
            $0.loginID(email, type: .email)
        }
        let controller = OwnID.flows.boost.createPasskey.start(context)
        self.controller = controller

        Task { @MainActor [weak self] in
            let result = await controller.whenSettled()
            guard let self else { return }

            self.controller = nil
            self.isRunning = false
            result
                .onSuccess { response in
                    switch response {
                    case .login(let response):
                        // Use response to update the app session, then publish the next UI state or effect.
                    case .createPasskey(let response):
                        // Keep response for registration and publish the next UI state or effect.
                    }
                }
                .onCanceled { reason in
                    // Use reason to publish the app state appropriate for cancellation.
                }
                .onError { failure in
                    // Use failure to publish app-owned error or fallback state.
                }
        }
    }
}
```

See [Widget Callbacks](#widget-callbacks) and [Common Failures](#common-failures) for response and failure handling.

See the Advanced Demo's [custom login button](../../Demo/DemoAdvanced/App/Views/Flows/Boost/BoostLoginScreen.swift) and [flow owner](../../Demo/DemoAdvanced/App/Views/Flows/Boost/EmailOtpLoginViewModel.swift) for a complete example.

### Limit Login Authentication Operations

An app-owned login entry point can represent a specific authentication choice, such as “Login via email OTP”. Use `allowedAuthOperations` to limit Boost Login to the authentication categories offered by that entry point. This option is available only for Boost Login.

The available categories are `.passkey`, `.emailVerification`, and `.phoneNumberVerification`. The `.passkey` category allows both signing in with a passkey and creating a passkey when Boost Login offers that path. When `allowedAuthOperations` is omitted or empty, Boost Login uses its standard behavior.

Configure the context inside the flow owner described above, then start Boost Login with that context:

```swift
let context = BoostFlowContext {
    $0.loginID(email, type: .email)
    $0.allowedAuthOperations = [.emailVerification]
}
```

Pass this context to the Boost Login start call shown above. If Boost Login cannot complete with the allowed categories, it settles with `.failure(.insufficientAuth(...))`.

## Security and Data Handling

- Treat `accessToken`, `sessionPayload`, and `ownIdData` as sensitive handoff values.
- Do not log passwords, provider tokens, OwnID Access Tokens, session payloads, or full authentication responses.
- Keep password login and manual registration available unless the product explicitly removes those fallbacks.
