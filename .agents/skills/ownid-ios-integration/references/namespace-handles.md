# Namespace Handles

Use this reference when an OwnID iOS SDK v4 integration needs context values,
provider bindings, or per-session overrides on SDK namespace handles. Keep exact
context values and required providers surface-specific.

For context values, read `context.md`. For provider callbacks, read
`providers.md`.

Source docs:

- `../../../../docs/setup/namespace-handles.md`
- `../../../../docs/setup/context.md`
- `../../../../docs/setup/providers.md`

Public API contracts: `OwnID`, `OwnIDNamespace`, `OwnIDInstance`, `Context`,
`Authz`, and `OwnIDProvidersRegistrar`.

## Mental Model

Namespace handles can carry two independent payloads:

- context: caller-supplied auth/display input for SDK calls that read context;
- providers: app-owned callback capabilities that SDK surfaces can invoke.

Start from the top-level namespace handle for the surface being integrated, such
as `OwnID.flows`, `OwnID.headless`, or `OwnID.webBridge`.

`withContext` and `withProviders` return derived handles. Build the derived handle
before calling `start()`, `create()`, or another surface entry point, then keep
using that returned handle for the sequence.

## Integration Rules

- Read the selected surface reference first; it decides whether context or
  providers are needed and which auth input is valid.
- Put context as close as possible to the concrete SDK call or screen session
  when the selected surface reads context.
- Use `setContext` only for intentional ambient context that later calls from
  the current handle should inherit. Clear it on sign-out, account switch, tenant
  switch, or any equivalent boundary.
- Register app-wide providers with `OwnID.setProviders` after SDK
  initialization and before surfaces that need those capabilities.
- Use `withProviders` only when one concrete surface session must override
  app-wide provider behavior.
- Keep provider registrar and builder objects inside the provider block.

## Edge Semantics

- `withContext` returns a derived handle whose context is built only from the
  block. Unset context fields do not inherit parent context values.
- `setContext` updates current context in place: assigned fields replace
  current values, unassigned fields stay unchanged, and assigning `nil` clears
  that field.
- `withProviders` returns a derived handle only when the block registers at least
  one provider. An empty block is a no-op and returns the current handle.
- `setProviders` updates current provider bindings in place only for provider
  types registered in the block. Existing bindings for provider types omitted
  from the block remain unchanged.

## Derived Handle Pattern

1. Register app-wide providers with `OwnID.setProviders { ... }` in startup
   setup after SDK initialization.
2. At the call site, start from the selected surface namespace.
3. Add `.withContext { ... }` when the selected surface needs auth or
   display input.
4. Add `.withProviders { ... }` only when this one surface session needs a
   provider override.
5. Call the selected surface entry point on the returned handle.

## Review Checks

- The selected surface reference was used to choose `.start(...)`,
  `.fromToken(...)`, `accountDisplayName`, or no context.
- Context is attached near the concrete SDK surface/session unless ambient
  current context is intentional.
- App-wide providers are registered once at startup; scoped overrides are
  limited to the surface session that needs different behavior.
- The returned derived handle is used for the whole sequence it starts.
