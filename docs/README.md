# Documentation

Use this page as a compact map of the public iOS SDK documentation.

## Upgrades

- [Version 3 to Version 4](upgrade/v3-to-v4.md): high-level changes, dependency updates, provider migration, and flow-specific upgrade notes.

## Setup

- [Configuration](setup/configuration.md): initialization sources, environment, region, language, and logging.
- [Namespace Handles](setup/namespace-handles.md): how context values and provider bindings attach to SDK namespace handles.
- [Context](setup/context.md): login ID, Access Token, account display name, `withContext`, `setContext`, and `clearContext`.
- [Providers](setup/providers.md): app-owned authentication providers, social sign-in setup, and provider bindings used by SDK flows.

## Flows

- [Boost Flow](flows/boost-flow.md): OwnID login widgets and create-passkey widgets for account creation.
- [Elite Flow](flows/elite-flow.md): guided OwnID-hosted authentication inside the app.
- [Passkey Enrollment](flows/passkey-enrollment.md): passkey creation from signed-in account screens.
- [Headless](flows/headless.md): SDK orchestration with app-owned UI.

## Integration

- [Operation UI](integration/operation-ui.md): app-hosted SDK operation screens.
- [WebBridge](integration/webbridge.md): OwnID actions from app-hosted WKWebView content.

## Customization

- [Themes and Colors](customization/themes-and-colors.md): shared theme and color-token setup for widgets and operation UI.
- [Localization](customization/localization.md): localized UI text customization for widgets and operation UI.
- [Boost Widget Customization](customization/boost-widgets.md): Boost widget appearance and behavior.

## Examples

- [DemoBase](../Demo/DemoBase): standard SDK setup, Boost Flow, Elite Flow, Headless, Passkey Enrollment, and example identity-provider wiring.
- [DemoAdvanced](../Demo/DemoAdvanced): customized Boost widgets, app-hosted operation UI, low-level API and operation scenarios, Headless, and Google provider wiring.
