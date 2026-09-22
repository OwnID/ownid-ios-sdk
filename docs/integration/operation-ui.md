# Operation UI

OwnID supports two presentation paths for supported operation UI: SDK-hosted default UI, or app-hosted UI. In both paths, the SDK drives operation state, validation, resend, cancellation, and settlement.

This applies to login ID collection, email verification, and phone verification. Use app-hosted UI when the app owns where the operation appears; otherwise, start the operation directly and let the SDK present its default UI container.

## Contents

- [Minimal Integration](#minimal-integration)
- [Examples](#examples)
- [Prerequisites](#prerequisites)
- [SDK-Hosted Default UI](#sdk-hosted-default-ui)
- [App-Hosted UI Lifecycle](#app-hosted-ui-lifecycle)
- [App-Owned Presentation](#app-owned-presentation)
- [Settlement, Cancellation, and Failures](#settlement-cancellation-and-failures)
- [Custom Content](#custom-content)
- [UI Error Text](#ui-error-text)

## Minimal Integration

Choose the operation, apply `appHostedComponent`, keep the [`OwnIDOperationUIController`](../../OwnIDSwiftUI/Sources/OwnIDOperationUIHosting.swift) in SwiftUI state, render [`OwnIDOperationView`](../../OwnIDSwiftUI/Sources/OwnIDOperationView.swift), and await settlement. In the example below, `operations` is the scoped operation namespace for the current integration context. Build that scoped handle before the availability check and use the same entry for `isAvailable()` and `start()`.

Availability is a preflight signal only. Use it to hide or disable unavailable actions, but still handle cancellation and typed failures from the started operation. An operation entry remains bound to the OwnID instance and context scope from which it was obtained; reacquire it after that instance is replaced or destroyed.

If the task owner stops awaiting before settlement, keep rendering the controller or explicitly abort the operation during cleanup.

```swift
import OwnIDCore
import OwnIDSwiftUI

@State private var operationUIController:
    OwnIDOperationUIController<AccessOrProofToken, EmailVerificationOperationFailure>?

func startEmailVerification() {
    let scopedOperations = operations.withContext { context in
        context.authz = .start(email, type: .email)
    }

    let emailVerificationOperation = scopedOperations.verifications.email.appHostedComponent

    Task { @MainActor in
        guard await emailVerificationOperation.isAvailable() else { return }

        let startedOperationUIController = emailVerificationOperation.start()
        operationUIController = startedOperationUIController

        await startedOperationUIController.whenSettled()
            .onSuccess { token in
                // Continue with the Access Token or Proof Token.
            }
            .onCanceled { reason in
                // Handle user close, timeout, or system cancellation.
            }
            .onError { error in
                // Log and map to app UI.
            }

        if operationUIController === startedOperationUIController {
            operationUIController = nil
        }
    }
}
```

Render the operation UI controller while it is active.

```swift
var body: some View {
    VStack {
        Button("Verify email") {
            startEmailVerification()
        }

        if let operationUIController {
            OwnIDOperationView(operationUIController: operationUIController)
        }
    }
}
```

## Examples

- [`OperationLoginIdCollectScreen.swift`](../../DemoAdvanced/App/Views/Ops/OperationLoginIdCollectScreen.swift)
- [`OperationVerificationScreen.swift`](../../DemoAdvanced/App/Views/Ops/OperationVerificationScreen.swift)
- [`DemoOperationDialog.swift`](../../DemoAdvanced/App/Views/Ops/DemoOperationDialog.swift)

## Prerequisites

- Add the SwiftUI SDK as described in [Install](../../README.md#install) and initialize OwnID in [Configuration](../setup/configuration.md).
- Scope each operation attempt with the login ID, Access Token, or other values that operation needs; see [Context](../setup/context.md) and [Namespace Handles](../setup/namespace-handles.md).
- For app-hosted UI, build the app-owned SwiftUI container for embedded, sheet, dialog, overlay, or full-screen presentation and keep the operation UI controller strongly referenced while the UI owns that operation.
- Keep app authentication, session, retry, or fallback UI available for unavailable, canceled, or failed operation attempts.

## SDK-Hosted Default UI

When the app starts a supported operation directly, without `appHostedComponent`, the optional `OwnIDSwiftUI` product supplies the operation content and presents it in its default bottom-sheet container. The app still owns the returned operation controller and must observe its terminal result; showing the sheet does not turn a cancellation or failure into success.

Start SDK-hosted UI while the app has an active, presentation-capable window. The default context lookup selects an eligible foreground app window. If the app has multiple scenes or must bind the operation to a particular owner, register the intended window, scene, or custom `UIContextProvider` as described in [Providers](../setup/providers.md) before starting. If the SDK cannot present the UI—for example, because no usable presentation context is available or another default presentation is active—the operation settles with a typed failure or cancellation. Keep fallback UI available and do not assume that a call to `start()` means that a sheet was shown.

Use `appHostedComponent` whenever the app needs to own the surface, dismissal binding, or surrounding navigation. Core-only integrations do not include the SwiftUI default operation UI.

## App-Hosted UI Lifecycle

```mermaid
flowchart LR
    A["App starts<br/>supported operation"] --> B["appHostedComponent"]
    B --> C["SDK returns<br/>UI controller"]
    C --> D["App renders<br/>OwnIDOperationView"]
    D --> E{"User action /<br/>SDK state"}
    E -->|"success"| F["App continues<br/>with payload"]
    E -->|"cancel"| G["App keeps retry<br/>or fallback UI"]
    E -->|"failure"| H["App maps typed<br/>operation failure"]
```

## App-Owned Presentation

App-hosted UI owns where the SDK operation UI is rendered. The SDK still owns operation state and settlement. Your UI should call the callbacks exposed by the operation UI state instead of completing or canceling from unrelated app state.

Supported app-hosted operation UI:

- Login ID collection: `operations.loginID.collect.appHostedComponent`
- Email verification: `operations.verifications.email.appHostedComponent`
- Phone verification: `operations.verifications.phone.appHostedComponent`

Both presentation patterns below require starting the operation through `appHostedComponent`. The difference is only where the returned `OwnIDOperationUIController` is rendered.

### Embedded

After starting with `appHostedComponent`, render `OwnIDOperationView` directly inside the screen. Removing it before settlement cancels the operation as a user close.

```swift
if let operationUIController {
    OwnIDOperationView(operationUIController: operationUIController)
}
```

### Dialog, Sheet, or Overlay

After starting with `appHostedComponent`, use [`OwnIDUIContainerController`](../../OwnIDSwiftUI/Sources/OwnIDUIContainerController.swift) when the operation UI is inside an app-owned sheet, dialog, overlay, or full-screen presentation.

Keep the started `OwnIDOperationUIController` strongly referenced while the UI owns that operation or presentation. Clear it after `whenSettled()` returns, or after the app-owned container close path has been reported. Create a new `OwnIDUIContainerController` for each presentation cycle, pass it to `OwnIDOperationView`, attach `.ownIDOperationContainer(...)` to the presented container root, and discard it after the container closes.

Do not reuse an `OwnIDUIContainerController` after it closes. Removing `OwnIDOperationView` is not a replacement for the container close lifecycle; report dismissal through the container modifier. Call `markOpened()` and `markClosed()` manually only for non-SwiftUI containers.

If the UI stops owning an unsettled operation without rendering `OwnIDOperationView` or without reporting the app-owned container close, call `abort(reason:)` with a meaningful `Reason`.

```swift
var body: some View {
    content
        .overlay {
            if let presentedOperationUIController = operationUIController {
                DemoOperationDialog(
                    operationUIController: presentedOperationUIController,
                    onDismiss: {
                        if operationUIController === presentedOperationUIController {
                            operationUIController = nil
                        }
                    }
                )
                // OwnIDUIContainerController is single-use. Reset the dialog state
                // when a new operation UI controller is presented.
                .id(presentedOperationUIController.operationID)
            }
        }
}
```

```swift
import OwnIDCore
import OwnIDSwiftUI

struct DemoOperationDialog<Success: Sendable, Failure: OperationFailure>: View {
    let operationUIController: OwnIDOperationUIController<Success, Failure>
    @StateObject private var containerController: OwnIDUIContainerController

    init(
        operationUIController: OwnIDOperationUIController<Success, Failure>,
        onDismiss: @escaping @MainActor () -> Void
    ) {
        self.operationUIController = operationUIController
        _containerController = StateObject(wrappedValue: OwnIDUIContainerController(closeAction: onDismiss))
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()
                .onTapGesture { containerController.close() }

            OwnIDOperationView(
                operationUIController: operationUIController,
                containerController: containerController
            )
        }
        .ownIDOperationContainer(containerController)
    }
}
```

## Settlement, Cancellation, and Failures

`whenSettled()` delivers exactly one terminal [`OperationResult`](../../OwnIDCore/Sources/Operation/OperationCapability.swift):

| Result | Meaning | App handling |
| --- | --- | --- |
| `success(value)` | The operation completed. | Continue with the returned value and update app-owned state. |
| `canceled(reason)` | The user, app-owned container, timeout, SDK scope, or platform canceled the attempt. | Keep the current app session intact, clear the controller, and offer retry or fallback when appropriate. |
| `failure(error)` | A typed input, backend, provider, UI-integration, or runtime failure stopped the attempt. | Branch on the concrete failure enum, keep fallback UI available, and start a fresh operation for retry. |

Canceling the task that is waiting in `whenSettled()` does not cancel the operation. If the owner is going away before settlement, keep rendering the controller until it settles or call `abort(reason:)`. A controller represents one run and cannot be restarted; after settlement, call `start()` again on the same bound operation entry to create a new controller. For app-hosted presentation, create a fresh single-use `OwnIDUIContainerController` for the new presentation cycle; `start()` does not create that container. Reacquire the entry only after its OwnID instance is replaced or destroyed.

Built-in and custom content may show recoverable validation or verification errors through `UIError` while the operation remains active. Use `UIError.localizedMessage` or an `errorTextProvider` for visible copy. Use the terminal result and typed failure enum for routing; do not branch on `message`, visible text, or `ErrorCode` alone.

## Custom Content

Use custom content when an app-hosted operation should keep SDK-owned operation state and settlement, but render one or more supported screens with app UI. Start the operation with `appHostedComponent` and render the returned `OwnIDOperationUIController` with `OwnIDOperationView`; content overrides only change the content rendered inside that host.

Custom content owns rendering, focus behavior, visible busy indicators, error display, and wiring user actions to the supplied operation UI state callbacks. The SDK still owns validation, resend/cancel/"not you" handling, timeout, abort, and final settlement.

Supported overrides:

- `withLoginIDCollectContent` replaces login ID collection content. It should update through `onLoginIDChange`, submit through `onContinue`, preserve keyboard and autofill hints from the collectable login ID types, use `strings.error` for login ID validation errors, and use `errorTextProvider` or the current `UIError.localizedMessage` for other display errors.
- `withEmailVerificationContent` / `withPhoneVerificationContent` replace verification content. They should use the UI state's `challenge` for OTP length, resend policy, and the delivery destination shown to the user (`challenge.channel.channel`), normalize OTP input to digits, submit through `onCodeEntered` only when the required length is entered and the operation is not busy, reset challenge-scoped input when `challenge.challengeID` changes, clear input on visible errors, and invoke resend, cancel, and "not you" only from matching user actions.

```swift
OwnIDOperationView(operationUIController: operationUIController)
    .withLoginIDCollectContent { state, strings, errorTextProvider, isReadyForInitialFocus in
        CustomLoginIDCollectView(
            state: state,
            strings: strings,
            errorTextProvider: errorTextProvider,
            isReadyForInitialFocus: isReadyForInitialFocus
        )
    }
```

Each content override receives:

| Value | Purpose |
| --- | --- |
| UI state | Current fields, errors, available actions, and callbacks. |
| Strings | Localized SDK strings for that operation; see [Localization](../customization/localization.md). |
| Error text provider | Optional mapper from `ErrorCode` to display text. |
| `isReadyForInitialFocus` | `true` when the surrounding presentation is ready for one-time initial focus. |

Custom operation content can read `EnvironmentValues.ownIDTheme` inside `OwnIDOperationView`; see [Themes and Colors](../customization/themes-and-colors.md).

For SDK-wide theme and color customization, see [Themes and Colors](../customization/themes-and-colors.md). For localized UI text customization, see [Localization](../customization/localization.md).

## UI Error Text

Use `errorTextProvider` when SDK-rendered operation content should map OwnID UI errors to app-specific copy. The provider receives an [`ErrorCode`](../../OwnIDCore/Sources/Models/ErrorCode.swift), which is a localization key for visible text.

[`UIError`](../../OwnIDCore/Sources/Models/UIError.swift) represents text that is already meant to be visible inside the current SDK operation UI state. Show `UIError.localizedMessage` when the SDK default copy fits the screen, or use `errorTextProvider` to map `UIError.errorCode` to app copy. Some recoverable verification errors are shown this way so the user can correct a code or resend without the operation settling.

Do not use visible error text, `OperationFailure.message`, or `ErrorCode` for semantic branching. Semantic handling belongs to the typed result or failure returned by `operationUIController.whenSettled()`.

```swift
OwnIDOperationView(
    operationUIController: operationUIController,
    errorTextProvider: { code in
        switch code {
        case .network:
            return "Check your connection and try again."
        default:
            return "Something went wrong. Try again."
        }
    }
)
```
