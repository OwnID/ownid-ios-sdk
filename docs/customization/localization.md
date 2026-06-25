# Localization

OwnID UI text is localized by the SDK. In most integrations, rely on the default system language tracking described in [Configuration](../setup/configuration.md#language) and use the default text for widgets and operation screens. Override strings only when a specific widget or operation screen needs app-specific copy.

Main customization points:

- Boost widgets accept explicit `BoostWidgetStrings` for the widget instance.
- App-hosted operation UI passes localized operation strings into custom content builders.
- Built-in operation UI accepts `errorTextProvider` for app-specific error copy.

## Boost Widget Text

Use [`BoostWidgetStrings`](../../OwnIDCore/Sources/UI/Capability/BoostWidgetStringsProvider.swift) when one widget needs custom text. If `widgetStrings` is omitted, the widget uses SDK-localized text for the active language.

| Field | Use |
| --- | --- |
| `skipPassword` | Boost button label and custom icon-button accessibility label. Keep it short and meaningful. |
| `or` | Separator text passed to the widget row. |

```swift
import OwnIDCore
import OwnIDSwiftUI

OwnIDLoginWidget(
    onLogin: handleLogin,
    loginID: email,
    widgetStrings: BoostWidgetStrings(
        skipPassword: "Continue with passkey",
        or: "or"
    )
)
```

## Operation UI Text

When you use app-hosted operation UI, OwnID resolves the localized strings for the active operation and passes them to your custom content. Use those values for titles, messages, placeholders, and actions so custom UI stays aligned with SDK localization.

### String Models

Operation string models are specific to the screen:

For verification messages, `%CODE_LENGTH%` is the OTP length from the active challenge and `%LOGIN_ID%` is the delivery destination from the active challenge.

| Operation UI | Strings type | Fields |
| --- | --- | --- |
| Login ID collection | [`LoginIDCollectStrings`](../../OwnIDCore/Sources/UI/Capability/LoginIDCollectStringsProvider.swift) | `title`, `message`, `placeholder`, `cancel`, `cta`, `error` |
| Email verification | [`EmailVerificationStrings`](../../OwnIDCore/Sources/UI/Capability/EmailVerificationStringsProvider.swift) | `title`, `message`, `description`, `resend`, `cancel`, `notYou` |
| Phone verification | [`PhoneVerificationStrings`](../../OwnIDCore/Sources/UI/Capability/PhoneVerificationStringsProvider.swift) | `title`, `message`, `description`, `resend`, `cancel`, `notYou` |

### Error Text

For login ID collection validation errors, use `strings.error`. For other SDK UI errors, use `errorTextProvider`; see [Operation UI](../integration/operation-ui.md#ui-error-text).

### Custom Content Example

```swift
import OwnIDCore
import OwnIDSwiftUI

OwnIDOperationView(operationUIController: operationUIController)
    .withLoginIDCollectContent { state, strings, errorTextProvider, isReadyForInitialFocus in
        CustomLoginIDCollectView(
            state: state,
            title: strings.title,
            message: strings.message,
            placeholder: strings.placeholder,
            confirmText: strings.cta,
            cancelText: strings.cancel,
            errorTextProvider: errorTextProvider,
            isReadyForInitialFocus: isReadyForInitialFocus
        )
    }
```
