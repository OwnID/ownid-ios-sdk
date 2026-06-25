# Providers

Use this reference when an OwnID iOS SDK v4 integration needs app-owned
provider callbacks. Provider parameters, return types, helper setup, and full
snippets live in the public source docs.

Source docs:

- `../../../../docs/setup/providers.md`
- `../../../../docs/setup/namespace-handles.md`

Public API contracts: `OwnID.setProviders`, `withProviders`,
`OwnIDProvidersRegistrar`, `SessionCreate`, `PasswordAuthenticate`, and
`SignInWithSocial`.

## Contents

- [Boundary](#boundary)
- [Integration Rules](#integration-rules)
- [Scope Semantics](#scope-semantics)
- [Provider Contracts](#provider-contracts)
- [Source-Only Helpers](#source-only-helpers)
- [Review Checks](#review-checks)

## Boundary

Providers connect OwnID SDK surfaces to app-owned capabilities. The app still
owns session state, password verification, token storage, logout, navigation,
analytics, backend identity model, social SDK setup, Apple Developer setup,
Google Cloud setup, signing, and error handling.

Provider categories:

- `sessionCreate`: turn an OwnID-authenticated result into an app session.
- `passwordAuthenticate`: let a supported OwnID surface ask the app/backend to
  verify a password. Never send passwords to OwnID.
- Social providers such as Google: let supported OwnID social steps call the
  app's provider SDK and receive a provider ID token.
- Sign in with Apple is built into `OwnIDCore`; it is not registered through
  `OwnIDProvidersRegistrar`.
- Source-only identity helpers can wire provider callbacks for a specific
  identity platform.

## Integration Rules

- Read the selected surface reference first. Register only providers that the
  selected surface or hosted page can actually call.
- Register providers after successful SDK initialization and before starting
  the SDK surface that needs them.
- Register providers as high as practical, normally once with
  `OwnID.setProviders` during startup.
- Use `withProviders` only when one concrete surface session intentionally
  needs different provider behavior from the app-wide bindings.
- Keep the registrar and provider builder objects inside the provider block.
- Use `isAvailable` when a provider can handle only some requests.
- Keep provider construction simple; failures thrown while building the block
  are not converted by OwnID.

## Scope Semantics

- `setProviders` updates current provider bindings in place. Provider types
  declared in the block replace existing bindings of the same type; supported
  provider types omitted from the block remain unchanged.
- `withProviders` returns a derived handle when the block registers at
  least one provider. The child inherits other bindings and overrides only the
  provider types registered in the block.
- An empty `withProviders` or `setProviders` block is a no-op.
- Keep using the returned derived handle. Calling back into top-level `OwnID`
  entry points uses the default handle again.

## Provider Contracts

Open `../../../../docs/setup/providers.md` before writing concrete provider
code. Verify exact parameters and return values against the public API comments
and source for the selected SDK release.

Critical contracts:

- `sessionCreate.create` receives authenticated login/session data and returns
  Swift `Result<SessionOutput, any Error & Sendable>`.
- `passwordAuthenticate.authenticate` verifies user-entered passwords through
  the app backend or identity provider and returns Swift
  `Result<SessionOutput, any Error & Sendable>`.
- Google/social provider handlers return `SocialResult`.
- Provider callbacks run on the main actor where the public protocol or builder
  requires it.
- Provider failure handling is surface-specific. In Elite Flow and WebBridge,
  `sessionCreate` and `passwordAuthenticate` failures are returned to the hosted
  page as a failed provider result, not as `FlowResult.failure`; SDK/WebView
  infrastructure failures are reported separately.

## Source-Only Helpers

OwnID may publish provider helper source files. Copy helpers unchanged into the
app target first, then adapt only target-specific wiring when required.

- Google helper: `../../../../Providers/OwnIDSignInWithGoogleProvider.swift`.
- For SAP Customer Data Cloud/Gigya, use the public providers docs and the
  source-only helper `../../../../Providers/OwnIDGigyaProviders.swift`.

Helpers may contain SDK-owned SPI imports because OwnID owns the helper. Treat
those imports as helper implementation details, not app integration patterns.

## Review Checks

- Providers are registered globally unless a scoped override is intentional.
- The integration registers only provider types the selected surface can call.
- Passwords go only to the app backend or identity provider.
- Provider callbacks return public contract result types from the public API.
- Apple Developer, Google Cloud, OAuth, signing, backend, and production tenant
  setup is tracked as explicit external work.
