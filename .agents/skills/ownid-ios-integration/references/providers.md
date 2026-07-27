# Providers

Use this reference when an OwnID iOS SDK v4 integration needs app-owned
provider callbacks. Provider parameters, return types, helper setup, and full
snippets live in the SDK docs, source, and provider examples.

Source docs:

- `../../../../docs/setup/providers.md`
- `../../../../docs/setup/access-token.md`
- `../../../../docs/setup/namespace-handles.md`

SDK contracts: `OwnID.setProviders`, `withProviders`,
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
analytics, backend identity model, social SDK setup, and error handling.

Provider categories:

- `sessionCreate`: turn an OwnID-authenticated result into an app session.
- `passwordAuthenticate`: let a supported OwnID surface ask the app/backend to
  verify a password. Keep passwords inside the app/identity-provider
  authentication boundary.
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
- Complete each provider registration with its required handler: `create` for
  `sessionCreate`, `authenticate` for `passwordAuthenticate`, and `signIn` for
  `signInWithGoogle`.

## Scope Semantics

- `OwnID.setProviders` updates top-level provider bindings in place. Provider
  types declared in the block replace existing bindings of the same type;
  supported provider types omitted from the block remain unchanged.
- `withProviders` returns a derived handle when the block registers at
  least one provider. The child inherits other bindings and overrides only the
  provider types registered in the block.
- Concrete `flows` and `webBridge` namespace handles expose
  `withProviders`, not in-place `setProviders`.
- An empty `withProviders` or `OwnID.setProviders` block is a no-op.
- Keep using the returned derived handle. Calling back into top-level `OwnID`
  entry points uses the top-level bindings again.

## Provider Contracts

Open `../../../../docs/setup/providers.md` before writing concrete provider
code. Verify exact parameters and return values against production API/source
and maintained provider/demo examples for the selected SDK release.

Critical contracts:

- `sessionCreate.create` receives authenticated login/session data and returns
  Swift `Result<SessionOutput, any Error & Sendable>`.
- `passwordAuthenticate.authenticate` verifies user-entered passwords through
  the app backend or identity provider and returns Swift
  `Result<SessionOutput, any Error & Sendable>`.
- Google/social provider handlers return `SocialResult`.
- `sessionCreate` `create`/`isAvailable` and `passwordAuthenticate`
  `authenticate`/`isAvailable` callbacks run on the main actor. Google
  `signIn`, `cancel`, and `signOut` also run on the main actor.
- Provider callbacks must return after app-owned work finishes. If that work
  uses blocking APIs, dispatch it away from the main actor inside the callback
  and await completion.
- Provider failure handling is surface-specific. In Elite Flow and WebBridge,
  `sessionCreate` and `passwordAuthenticate` failures are returned to the hosted
  page as a failed provider result, not as `FlowResult.failure`; SDK/WebView
  infrastructure failures are reported separately. Direct API calls report a
  missing or failed provider through that call's typed failure result.

## Source-Only Helpers

Copy OwnID-published provider helper source files unchanged into the app target.
Keep app-owned dependencies, configuration, and provider registration outside
the helper.

- Google helper: `../../../../Providers/OwnIDSignInWithGoogleProvider.swift`.
- For SAP Customer Data Cloud/Gigya, use the providers docs and the
  source-only helper `../../../../Providers/OwnIDGigyaProviders.swift`.

## Review Checks

- Shared providers are registered through top-level `OwnID.setProviders`;
  scoped overrides stay with the derived surface handle that uses them.
- The integration registers only provider types the selected surface can call.
- Passwords remain inside the app backend or identity-provider boundary.
- Provider callbacks return the exact result types required by the selected SDK
  release.
- Apple Developer, Google Cloud, OAuth, signing, backend, and production tenant
  setup is tracked as explicit external work.
