# UI Customization

Use this when integrating OwnID iOS SDK v4 UI in a client app. Keep the answer
on public native UI surfaces: `OwnIDSwiftUI`, operation UI controllers, SwiftUI
modifiers, and public documentation examples.

Primary source docs:

- `../../../../docs/customization/themes-and-colors.md`
- `../../../../docs/customization/boost-widgets.md`
- `../../../../docs/integration/operation-ui.md`
- `../../../../docs/customization/localization.md`

## Contents

- [Choose The Customization Layer](#choose-the-customization-layer)
- [Themes And Colors](#themes-and-colors)
- [Language, Strings, And Error Text](#language-strings-and-error-text)
- [Boost Widgets](#boost-widgets)
- [App-Hosted Operation UI](#app-hosted-operation-ui)
- [Validation And Accessibility Guardrails](#validation-and-accessibility-guardrails)

## Choose The Customization Layer

Pick the narrowest public layer that matches the app requirement.

| Requirement | Public layer | Notes |
| --- | --- | --- |
| Make SDK SwiftUI match app appearance | `OwnIDTheme`, `OwnIDColors`, `theme:` parameters, `.ownIDTheme(...)` for SDK-hosted UI | Use semantic color tokens and OwnID theme APIs. |
| Change Boost widget text for one screen | `BoostWidgetStrings` on the widget | Prefer SDK localization for global language behavior. |
| Force SDK UI language | `languages` during initialization or `OwnID.setLanguage(...)` | BCP 47 tags. This switches from automatic system language tracking to explicit tags. |
| Replace widget icon/checkmark/spinner/trailing text | Boost widget modifiers/slots | The widget still owns throttling, flow state, callbacks, and accessibility label source. |
| Put supported operation UI inside app layout/dialog/sheet | `useAppHostedComponent` plus `OwnIDOperationView` | Supported for login ID collection, email verification, and phone verification. |

## Themes And Colors

OwnID SwiftUI uses `OwnIDTheme`. It contains `OwnIDColors`, the semantic color
palette for OwnID controls, fields, progress, checkmark state, surfaces, and
error states.

Use `OwnIDTheme.capture(colorScheme:)` to derive tokens from the current SwiftUI
color scheme. Use `OwnIDTheme.capture(colorScheme:primary:onPrimary:)` when
OwnID primary controls need a specific brand/action color pair. Then override
only the needed `OwnIDColors` tokens such as `primary`, `onPrimary`, `surface`,
`onSurface`, `onSurfaceVariant`, `fieldBackground`, `progress`,
`progressTrack`, `iconButtonBorder`, or `checkmarkButtonBackground`.

There are two rendering paths:

- SDK-hosted UI is presented by the SDK outside the caller's current SwiftUI
  tree. Publish a theme snapshot near the app root with `.ownIDTheme { colorScheme, theme in ... }`.
  A later publication replaces the active snapshot for the current OwnID
  runtime.
- App-hosted UI is rendered at the current call site. `OwnIDLoginWidget`,
  `OwnIDCreatePasskeyWidget`, `OwnIDBoostButton`, and `OwnIDOperationView`
  resolve an explicit `theme:` first. Widgets then fall back to
  `EnvironmentValues.ownIDTheme` and then current `ColorScheme`;
  `OwnIDOperationView` captures the current `ColorScheme` and accent color when
  no explicit theme is passed and provides the resolved theme to its subtree.

Custom operation content can read `EnvironmentValues.ownIDTheme`. Use those
tokens in app-owned replacement content so light/dark mode, brand colors, and
SDK state colors stay coherent.

## Language, Strings, And Error Text

Default behavior is SDK localization. Configure global language only when the
app must force OwnID text:

- initialization `configuration.languages = ["en-US"]`;
- later `OwnID.setLanguage(["en-US", "fr-FR"])`.
- restore automatic tracking with `OwnID.setLanguage([])`.

When a non-empty explicit language array is set, `Locale.preferredLanguages`
tracking stops until another `setLanguage` call or process restart. An empty
array keeps or restores automatic tracking. Resolution falls back from full tag
to language-only tag, then English, then embedded SDK fallback strings.

Use public text overrides only at these points:

- Boost widgets: pass `BoostWidgetStrings(skipPassword: ..., or: ...)`.
  `skipPassword` labels the button and is also the accessibility label passed
  to custom icon-button content. Keep it short and action-oriented.
- App-hosted operation UI: custom content receives operation-specific localized
  strings (`LoginIDCollectStrings`, `EmailVerificationStrings`,
  `PhoneVerificationStrings`). Use those values for titles, messages,
  placeholders, resend/cancel/not-you actions, and CTA text.
- Operation error copy: pass `errorTextProvider: (ErrorCode) -> String` to
  `OwnIDOperationView` when app-specific copy is needed. Otherwise built-in
  content displays the SDK `UIError.localizedMessage`.

## Boost Widgets

Boost UI entry points are:

- `OwnIDLoginWidget`;
- `OwnIDCreatePasskeyWidget`;
- `OwnIDBoostButton` for the shared row when the app owns flow state.

Both built-in widgets trim whitespace/newlines from `loginID`; blank values are
passed as no login ID. Keep the password/manual login or registration path
available next to the widget.

Supported customization:

- `theme: OwnIDTheme`;
- `widgetStrings: BoostWidgetStrings`;
- `showSpinner: Bool`;
- `position: OwnIDBoostButtonPosition`;
- `.iconButton { isBusy, isEnabled, action, accessibilityLabel in ... }`;
- `.checkmark { ... }` on `OwnIDCreatePasskeyWidget`;
- `.orText { text in ... }`, returning `EmptyView()` to hide it;
- externally owned `OwnIDLoginWidgetViewModel` or
  `OwnIDCreatePasskeyWidgetViewModel`;
- stable SwiftUI identity for repeated/dynamic widgets, and separate view
  models when state must survive navigation, row recycling, or conditional view
  replacement.

Slot guardrails:

- The icon-button slot receives a throttled action, localized accessibility
  label, busy state, and enabled state. Call `action` directly, respect
  `isEnabled`, and preserve an accessible label.
- Use `OwnIDSpinnerView(colors:style:)` when custom content should keep the SDK
  spinner. Derive matching semantic colors with
  `OwnIDSpinnerDefaults.colors(colors:)`, or pass `OwnIDSpinnerColors` for a
  local override.
- Configure widget-specific theme tokens with `theme:`. Use `.ownIDTheme(...)`
  near the app root for SDK-hosted UI.
- If `showSpinner: false`, provide another progress indication if the screen can
  otherwise look idle during a running flow.
- The create-passkey checkmark reflects the widget ViewModel's in-memory
  completion state. Store `ownIdData` in app state only while the current form
  login ID still matches the response login ID; clear it on `onReset` or form
  login ID mismatch.
- Use one externally owned widget view model per visible logical widget.

## App-Hosted Operation UI

Use app-hosted operation UI when the app owns placement or presentation chrome
but wants the SDK to own operation state, validation, resend, cancellation, and
settlement.

Supported operations:

- `ownIDOperations.loginID.collect`;
- `ownIDOperations.verifications.email`;
- `ownIDOperations.verifications.phone`.

Pattern:

1. Scope context as needed for the operation.
2. Select the concrete operation and apply `.useAppHostedComponent`.
3. Check availability when the operation exposes it.
4. Start the operation and retain the returned `OwnIDOperationUIController` in
   SwiftUI state.
5. Render `OwnIDOperationView(operationUIController: controller)` while active.
6. Await `controller.whenSettled()` and clear the retained controller when it
   is still the current one.

Presentation modes:

- Embedded: render `OwnIDOperationView` directly in the screen. Removing it
  before settlement cancels the operation with user-close semantics.
- Dialog/sheet/overlay/full-screen cover: create a fresh
  `OwnIDUIContainerController(closeAction:)` for each presentation cycle. The
  close action should start app-owned dismissal. Pass the controller to
  `OwnIDOperationView`, attach `.ownIDOperationContainer(containerController)`
  to the presented container root so `markOpened()`/`markClosed()` are reported,
  and route user dismissal through `containerController.close()`.

Custom content overrides are SwiftUI environment modifiers on the
`OwnIDOperationView` subtree:

- `.withLoginIDCollectContent { state, strings, errorTextProvider, isReadyForInitialFocus in ... }`;
- `.withEmailVerificationContent { state, strings, errorTextProvider, isReadyForInitialFocus in ... }`;
- `.withPhoneVerificationContent { state, strings, errorTextProvider, isReadyForInitialFocus in ... }`.

Each override receives UI state, localized strings, optional
`errorTextProvider`, and `isReadyForInitialFocus`. It owns rendering and
user-event wiring only. Complete, resend, and cancel through callbacks from the
supplied UI state.

Preserve these behavior contracts when replacing built-in content:

- Login ID collection: update through `onLoginIDChange`, continue through
  `onContinue`, preserve keyboard/autofill hints for the collectable login ID
  types, show login ID validation errors from `strings.error`, and show other
  UI errors from `errorTextProvider` or the current SDK UI error.
- Email/phone verification: accept/normalize OTP digits, submit through the UI
  state's `onCodeEntered` only when required length is reached and the operation
  is not busy, clear input on visible errors, and invoke resend, cancel, and
  "not you" only from the matching user action.
- Initial focus: request it only when `isReadyForInitialFocus` is true,
  especially in sheets/dialogs.

`OwnIDOperationView` covers app-hosted operation content for supported
operations. Native theme tokens affect OwnID SwiftUI widgets and app-hosted
operation UI.

## Validation And Accessibility Guardrails

For an integration answer, recommend the smallest meaningful app validation for
the changed surface:

- light and dark appearance screenshots or manual inspection for changed
  `OwnIDColors`;
- VoiceOver/accessibility scan for custom icon buttons, custom operation
  content, focus order, labels, and touch targets;
- Dynamic Type and narrow-width checks for widget trailing text and operation
  content;
- login/create-passkey callbacks after widget customization, including
  `onCancel`, `onError`, and `onReset` for create-passkey;
- operation dialog/sheet open, close, retry, resend, and settle paths when using
  app-hosted operation UI.

If a required visual change is not possible through the public surfaces above,
say so and ask whether the app should use app-owned UI or request SDK product
support.
