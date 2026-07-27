# Boost Widget Customization

Boost widgets are the SwiftUI entry points for login and create-passkey flows. This page covers widget customization only. For integration flow wiring, see [Boost Flow](../flows/boost-flow.md). For custom operation screens, see [Operation UI](../integration/operation-ui.md).

Both widgets trim whitespace and newlines from `loginID` before starting their flow. Blank values are ignored and passed as no login ID.

| Widget | Purpose |
| --- | --- |
| [`OwnIDLoginWidget`](../../OwnIDSwiftUI/Sources/Widget/OwnIDLoginWidget.swift) | Adds OwnID login to an existing login screen. |
| [`OwnIDCreatePasskeyWidget`](../../OwnIDSwiftUI/Sources/Widget/OwnIDCreatePasskeyWidget.swift) | Adds create-passkey to registration or account screens. |

## Contents

- [Customization Surface](#customization-surface)
- [Examples](#examples)
- [Theme and Text](#theme-and-text)
- [Spinner](#spinner)
- [Position](#position)
- [Icon Button Slot](#icon-button-slot)
- [Checkmark Slot](#checkmark-slot)
- [Separator Text](#separator-text)
- [Externally Owned View Model](#externally-owned-view-model)
- [Multiple Widgets and State Ownership](#multiple-widgets-and-state-ownership)

## Customization Surface

| Need | API |
| --- | --- |
| Match app colors, typography, shapes | [`theme: OwnIDTheme`](../../OwnIDSwiftUI/Sources/OwnIDTheme.swift); see [Themes and Colors](themes-and-colors.md) |
| Override widget text | [`widgetStrings: BoostWidgetStrings`](../../OwnIDCore/Sources/UI/Capability/BoostWidgetStringsProvider.swift); see [Localization](localization.md) |
| Hide the busy spinner | `showSpinner: Bool` |
| Show OwnID after the `or` separator | [`position: .end`](../../OwnIDSwiftUI/Sources/Components/OwnIDBoostButton.swift) |
| Replace the icon button | `.iconButton` modifier |
| Replace create-passkey success mark | `.checkmark` modifier |
| Hide or replace separator text | `.orText` modifier |
| Own widget state outside the SwiftUI view | [`OwnIDLoginWidgetViewModel`](../../OwnIDSwiftUI/Sources/Widget/OwnIDLoginWidgetViewModel.swift) / [`OwnIDCreatePasskeyWidgetViewModel`](../../OwnIDSwiftUI/Sources/Widget/OwnIDCreatePasskeyWidgetViewModel.swift) |
| Keep repeated widget state separate | Stable SwiftUI identity, or a separate externally owned view model per logical widget |

## Examples

Advanced examples show complete screen wiring:

- [Boost login example](../../Demo/DemoAdvanced/App/Views/Flows/Boost/BoostLoginScreen.swift)
- [Boost create-passkey example](../../Demo/DemoAdvanced/App/Views/Flows/Boost/BoostCreatePasskeyScreen.swift)

## Theme and Text

Pass an explicit `OwnIDTheme` when one widget should use stable theme values. For app-wide theme publishing, per-widget themes, and color-token guidance, see [Themes and Colors](themes-and-colors.md).

Use `widgetStrings` for the separator text and the icon-button accessibility label. For server-provided and app-provided localization, see [Localization](localization.md).

## Spinner

By default, widgets show a spinner while the Boost flow is running. Set `showSpinner: false` when your screen already shows progress elsewhere.

```swift
import OwnIDCore
import OwnIDSwiftUI
import SwiftUI

OwnIDLoginWidget(
    onLogin: handleLogin,
    loginID: email,
    showSpinner: false
)
```

When replacing the icon-button slot but keeping the OwnID spinner, use [`OwnIDSpinnerView`](../../OwnIDSwiftUI/Sources/Components/OwnIDSpinnerView.swift) in the custom slot. Pass `OwnIDSpinnerColors` for per-slot colors, or use `OwnIDSpinnerDefaults.colors(colors:)` to derive spinner colors from an [`OwnIDColors`](../../OwnIDSwiftUI/Sources/OwnIDColors.swift) palette.

## Position

By default, the OwnID action appears before the `or` separator. Keep this default when the widget appears before the app's password field.

Use `position: .end` when your screen places the widget after the password field. This keeps the separator between the password field and OwnID.

```swift
import OwnIDCore
import OwnIDSwiftUI
import SwiftUI

OwnIDLoginWidget(
    onLogin: handleLogin,
    loginID: email,
    position: .end
)
```

`start` and `end` follow the screen's layout direction, so the same value works for left-to-right and right-to-left languages.

## Icon Button Slot

Use `.iconButton` when you need to render the icon button with your own component.

The widget passes a throttled `action`, localized `accessibilityLabel`, busy state, and enabled state. Your button should call `action` directly, preserve the accessibility label, respect `isEnabled`, and keep a comparable control size and button semantics.

```swift
import OwnIDCore
import OwnIDSwiftUI
import SwiftUI

OwnIDLoginWidget(onLogin: handleLogin, loginID: email)
    .iconButton { isBusy, isEnabled, action, accessibilityLabel in
        // Your custom icon button.
        Button(action: action) {
            if isBusy {
                OwnIDSpinnerView()
            } else {
                Image(systemName: "person.badge.key")
            }
        }
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
    }
```

The slot receives:

| Parameter | Meaning |
| --- | --- |
| `isBusy` | The slot should show progress. This is `false` when `showSpinner` is `false`, even if a flow is running. |
| `isEnabled` | The button should accept taps. |
| `action` | The tap action that starts the flow. |
| `accessibilityLabel` | Localized label from `BoostWidgetStrings.skipPassword`. |

## Checkmark Slot

`OwnIDCreatePasskeyWidget` can show a checkmark after passkey creation succeeds. Replace it with `.checkmark`.

```swift
import OwnIDCore
import OwnIDSwiftUI
import SwiftUI

OwnIDCreatePasskeyWidget(
    onLogin: handleLogin,
    onNewPasskey: handleNewPasskey,
    onReset: resetCreatePasskeyState,
    loginID: email
)
.checkmark {
    // Your custom success mark.
    Image(systemName: "checkmark.circle.fill")
        .resizable()
        .scaledToFit()
        .foregroundColor(.green)
}
```

`OwnIDLoginWidget` does not render a checkmark because login does not keep completed create-passkey state.

The default checkmark is decorative. If completion must be announced, expose that state through surrounding screen UI or accessibility semantics.

## Separator Text

Use `.orText` to replace the separator text.

```swift
import OwnIDCore
import OwnIDSwiftUI
import SwiftUI

OwnIDLoginWidget(onLogin: handleLogin, loginID: email)
    .orText { value in
        // Your custom separator text.
        Text(value)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
```

If the app does not need a separator, return an empty view:

```swift
import OwnIDCore
import OwnIDSwiftUI
import SwiftUI

OwnIDLoginWidget(onLogin: handleLogin, loginID: email)
    .orText { _ in
        // Your custom hidden separator.
        EmptyView()
    }
```

## Externally Owned View Model

By default, each widget owns its view model. Provide your own view model when state must outlive a specific SwiftUI view instance or when you build custom OwnID UI for the same Boost flow.

```swift
import OwnIDCore
import OwnIDSwiftUI
import SwiftUI

@State private var viewModel = OwnIDLoginWidgetViewModel()

var body: some View {
    OwnIDLoginWidget(
        onLogin: handleLogin,
        loginID: email,
        viewModel: viewModel
    )
}
```

For create-passkey, externally owning the view model preserves its in-memory completion state while the view model stays alive:

```swift
import OwnIDCore
import OwnIDSwiftUI
import SwiftUI

@State private var createPasskeyViewModel = OwnIDCreatePasskeyWidgetViewModel()

OwnIDCreatePasskeyWidget(
    onLogin: handleLogin,
    onNewPasskey: handleNewPasskey,
    onReset: resetCreatePasskeyState,
    loginID: email,
    viewModel: createPasskeyViewModel
)
```

`OwnIDCreatePasskeyWidgetViewModel` keeps the latest create-passkey response only while the view model is alive. If the effective `loginID` changes, the widget clears the visible checkmark and emits `onReset`; if the login ID later matches the remembered response again, it can emit `onNewPasskey` again without starting a new flow. Tapping the widget while it is already showing the checkmark clears that visible state and emits `onReset` without starting a new flow.

## Multiple Widgets and State Ownership

SwiftUI widget identity is based on the surrounding view identity. In static screens, the default owned view model is enough.

For repeated or dynamic UI, render widgets from a `ForEach` with stable item IDs so SwiftUI does not reuse widget state for a different row:

```swift
import OwnIDCore
import OwnIDSwiftUI
import SwiftUI

ForEach(accounts, id: \.id) { account in
    OwnIDLoginWidget(
        onLogin: handleLogin,
        loginID: account.email
    )
}
```

When widget state must survive row recycling or custom widget composition, keep a separate view model for each logical widget and pass it into the widget. Do not share one view model between two widgets that are visible at the same time.

For navigation or conditional view replacement, hoist the view model to a stable parent that outlives the replaced view.

```swift
import OwnIDCore
import OwnIDSwiftUI
import SwiftUI

@State private var loginViewModel = OwnIDLoginWidgetViewModel()

OwnIDLoginWidget(
    onLogin: handleLogin,
    loginID: email,
    viewModel: loginViewModel
)
```

Own the view model externally when the checkmark state should survive SwiftUI view recreation; persist any longer-lived app state outside the SDK.
