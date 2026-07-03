# Themes and Colors

The SwiftUI SDK product (`OwnIDSwiftUI`) contains OwnID UI surfaces: Boost widgets, SDK-hosted operation UI, app-hosted operation UI, and reusable UI components. These UI surfaces are themed through [`OwnIDTheme`](../../OwnIDSwiftUI/Sources/OwnIDTheme.swift).

SDK-hosted UI needs a published theme to reuse your app theme. App-hosted UI resolves its theme at the call site and needs an explicit `theme` only for custom theme values or selected overrides.

## Contents

- [Theme Paths](#theme-paths)
- [Examples](#examples)
- [SDK-Hosted UI](#sdk-hosted-ui)
- [App-Hosted UI](#app-hosted-ui)
- [Build a Theme](#build-a-theme)
- [Color Tokens](#color-tokens)

## Theme Paths

| Path | Default | What to do |
| --- | --- | --- |
| SDK-hosted operation UI | Uses SDK light or dark defaults unless a theme is published. | Add [`.ownIDTheme()`](../../OwnIDSwiftUI/Sources/OwnIDTheme.swift) near your themed app root. Use `customize` only for overrides. |
| App-hosted operation UI | Captures the current `ColorScheme` and primary accent color unless `theme` is passed. | No extra setup. Pass `theme` only for custom theme values or selected overrides. |
| Custom operation content | Can read `EnvironmentValues.ownIDTheme` inside `OwnIDOperationView`. | Use it instead of hard-coded colors. |
| Boost widgets | Resolve explicit `theme`, then `EnvironmentValues.ownIDTheme`, then capture the current `ColorScheme` and primary accent color. | No extra setup. Pass `theme` only for custom theme values or selected overrides. |
| Widget subcomponents | Use built-in themed components. | Use slot modifiers for structural changes; see [Boost Widget Customization](boost-widgets.md). |

## Examples

- [Advanced app root example](../../Demo/DemoAdvanced/App/DemoAdvancedApp.swift): publishes the app theme for SDK-hosted OwnID UI with `.ownIDTheme(...)`.
- [Advanced Boost login screen](../../Demo/DemoAdvanced/App/Views/Flows/Boost/BoostLoginScreen.swift): renders a Boost widget inside the app SwiftUI hierarchy with an explicit widget theme.
- [Advanced Boost create-passkey screen](../../Demo/DemoAdvanced/App/Views/Flows/Boost/BoostCreatePasskeyScreen.swift): renders a create-passkey widget inside the app SwiftUI hierarchy with an explicit widget theme.

## SDK-Hosted UI

Default SDK-presented OwnID operation UI is started from your app code but rendered by the SDK. Because that UI is not a child of the caller's SwiftUI view, it cannot read the caller's local SwiftUI environment directly.

The modifier captures the current SwiftUI color scheme, applies your overrides, and publishes the resolved theme for the current OwnID runtime. The last published theme remains active for future SDK-hosted UI until another theme is published or the SDK is reinitialized.

Apply `.ownIDTheme()` near your app root when SDK-hosted OwnID UI should reuse app colors, even when you do not need custom colors.

```swift
RootView()
    .ownIDTheme()
```

Use `customize` only when SDK-hosted UI needs selected overrides.

```swift
RootView()
    .ownIDTheme { colorScheme, theme in
        let palette = AppPalette.ownIDPalette(for: colorScheme)
        theme.colors.primary = palette.primary
        theme.colors.onPrimary = palette.onPrimary
        theme.colors.surface = palette.surface
        theme.colors.onSurface = palette.text
        theme.colors.onSurfaceVariant = palette.secondaryText
        theme.colors.fieldBackground = palette.fieldBackground
    }
```

This publishing path is only for SDK-hosted UI. App-hosted UI resolves theme from its own call site, as described below.

## App-Hosted UI

Boost widgets and `OwnIDOperationView` are rendered directly inside your app's SwiftUI hierarchy, so `.ownIDTheme(...)` is not involved in this path.

### Boost Widgets

`OwnIDLoginWidget` and `OwnIDCreatePasskeyWidget` resolve their theme from the call site: explicit `theme` first, then `EnvironmentValues.ownIDTheme` when present, then a capture from the current `ColorScheme` and primary accent color. Use `theme` when that widget should use custom theme values or selected token overrides. Set `EnvironmentValues.ownIDTheme` manually only when an app-owned SwiftUI subtree should share one OwnID theme without passing `theme` to each view.

```swift
OwnIDLoginWidget(
    onLogin: handleLogin,
    loginID: email,
    theme: theme
)
```

### Operation UI

`OwnIDOperationView` resolves an explicit `theme` first and otherwise captures from the current `ColorScheme` and primary accent color. It then provides the resolved theme to its subtree through `EnvironmentValues.ownIDTheme`, so custom operation content can read the same tokens as built-in OwnID content.

```swift
OwnIDOperationView(
    operationUIController: operationUIController,
    theme: theme
)
```

Custom operation content can read `EnvironmentValues.ownIDTheme`. Treat those colors as the operation's semantic palette and use them instead of hard-coded colors.

```swift
private struct CustomLoginIDCollectView: View {
    @Environment(\.ownIDTheme) private var ownIDTheme
    @Environment(\.colorScheme) private var colorScheme

    private var colors: OwnIDColors {
        (ownIDTheme ?? OwnIDTheme.capture(colorScheme: colorScheme)).colors
    }

    var body: some View {
        Text("Continue")
            .foregroundStyle(colors.primary)
    }
}
```

## Build a Theme

`OwnIDTheme` contains `OwnIDColors`, the complete semantic color palette used by OwnID SwiftUI content.

| Part | Source by default | Used for |
| --- | --- | --- |
| `colors: OwnIDColors` | `OwnIDColors.capture(colorScheme:)` | OwnID-specific semantic colors for widgets, operation UI, fields, indicators, and state marks. |

`OwnIDTheme.capture(colorScheme:)` starts from the current SwiftUI `ColorScheme`, uses `.accentColor` as `primary`, maps system colors such as background, primary text, secondary text, separator, and system red, and keeps success/checkmark tokens on the SDK light or dark defaults. Parent `.tint(_:)` modifiers are not captured; pass `primary` and `onPrimary` when OwnID controls should use a specific app or brand color.

```swift
let theme = OwnIDTheme.capture(colorScheme: colorScheme)
```

Pass `primary` and `onPrimary` when OwnID controls should use a brand or app action color.

```swift
let theme = OwnIDTheme.capture(
    colorScheme: colorScheme,
    primary: palette.primary,
    onPrimary: palette.onPrimary
)
```

Then override selected tokens when needed.

```swift
var theme = OwnIDTheme.capture(
    colorScheme: colorScheme,
    primary: palette.primary,
    onPrimary: palette.onPrimary
)
theme.colors.surface = palette.cardBackground
theme.colors.onSurface = palette.text
theme.colors.onSurfaceVariant = palette.secondaryText
theme.colors.fieldBackground = palette.fieldBackground
theme.colors.iconButtonBorder = palette.border
```

## Color Tokens

Use [`OwnIDTheme.capture(...)`](../../OwnIDSwiftUI/Sources/OwnIDTheme.swift) to derive tokens from SwiftUI system colors, then override only what your app needs.

OwnID uses color values as provided. When overriding paired colors such as `primary` / `onPrimary` or `surface` / `onSurface`, keep the foreground color readable on the matching background.

| Token | Used for |
| --- | --- |
| `primary` / `onPrimary` | Primary actions, filled buttons, focused states, and primary icon content. |
| `error` | Validation and error states. |
| `surface` | OwnID containers and sheets. |
| `onSurface` | Primary text and content on `surface`. |
| `onSurfaceVariant` | Secondary text, helper text, outlines, and progress defaults. |
| `fieldBackground` | Text field and OTP field containers. |
| `progress` / `progressTrack` | Loading indicators. |
| `iconButtonBackground` / `iconButtonBackgroundDisabled` | Boost icon button containers. |
| `iconButtonBorder` | Boost icon button border. |
| `checkmarkButton` / `checkmarkButtonBackground` | Create-passkey success checkmark. |

`OwnIDSpinnerDefaults.colors(colors:)` maps `progress` and `progressTrack` to `OwnIDSpinnerColors` for `OwnIDSpinnerView`. Use that factory when custom spinner content should keep the same semantic theme mapping as built-in OwnID loading indicators.
