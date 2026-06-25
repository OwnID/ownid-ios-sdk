**Review Goal**

Evaluate whether the public iOS integration docs and key API contracts feel natural for an experienced iOS developer. 
****
**Main Instruction**

Start each section from the public documentation. Open source code only to validate the API shape, and open demo code only if the docs leave the integration flow unclear. The goal is to catch WTF moments, confusing contracts, naming issues, and places where an experienced iOS developer would not know what to do.

**Expected Reviewer Output**

Please write short notes grouped as:

* Release blocker
* Confusing but shippable
* Naming/API ergonomics issue
* Docs gap
* WTF moment

**1. Initialization + Session Create Provider — 8 min**

Start from docs:

* [`docs/setup/configuration.md`](docs/setup/configuration.md)
* [`docs/setup/context.md`](docs/setup/context.md)
* [`docs/setup/providers.md`](docs/setup/providers.md), only Session Create section

Scope:

* One init path only: `OwnID.initialize`
* `withContext` / `setContext` / `clearContext`
* `setProviders`
* `sessionCreate` only

Look for:

* Is it clear when context should be scoped vs global?
* Is `sessionCreate` understandable as the app session boundary?
* Do `@MainActor` callbacks feel acceptable?
* Is `Result<SessionOutput, any Error & Sendable>` ergonomic?
* Required handler uses `preconditionFailure` if omitted: acceptable setup-time trap or bad SDK behavior?

**2. Boost Flow — 10 min**

Start from docs:

* [`docs/flows/boost-flow.md`](docs/flows/boost-flow.md)

Scope:

* Basic Boost integration only
* Login widget
* Create-passkey widget

Look for:

* Does the login/register widget integration feel obvious?
* Are `onLogin`, `onNewPasskey`, `onReset`, `onError`, `onCancel` clear?
* Is `onReset` understandable?
* Is `ownIdData` handling clear enough?
* Is it obvious that password/manual fallback stays app-owned?

**3. Elite Flow — 10 min**

Start from docs:

* [`docs/flows/elite-flow.md`](docs/flows/elite-flow.md)

Scope:

* Events and controller lifecycle only

Look for:

* Are `onNativeAction`, `onFinish`, `onError`, `onClose` understandable?
* Is hosted-event vs native-controller result clear?
* Is it surprising that hosted `onError` / `onClose` can still make native controller settle successfully?
* Is retain controller / `whenSettled()` / `abort(reason:)` clear?

**4. Headless — 17 min**

Start from docs:

* [`docs/flows/headless.md`](docs/flows/headless.md)

Scope:

* Discover
* Additional auth requirements
* Passkey auth
* Email/phone verification lifecycle
* Login continuation
* Do not inspect every API/failure enum

Look for:

* Is discover → authRequired → operation/API → login understandable?
* Are `APIResult`, `OperationResult`, and `FlowResult` too much or acceptable?
* Is controller ownership clear?
* Is verification lifecycle clear: complete, resend, cancel?
* Is it clear that releasing a verification controller does not cancel server challenge?
* Are typed failures useful or overwhelming?

**5. App-Hosted Operation UI — 10-12 min**

Start from docs:

* [`docs/integration/operation-ui.md`](docs/integration/operation-ui.md)

Scope:

* App-hosted operation UI concept
* `OwnIDOperationView`
* Embedded rendering
* Dialog/sheet/overlay lifecycle
* `OwnIDUIContainerController`
* Do not deep-review generic entry types unless docs force the reader there

Look for:

* Is the concept clear: app owns presentation, SDK owns operation state?
* Is `OwnIDOperationView` usage obvious?
* Is embedded vs dialog/sheet lifecycle understandable?
* Is `OwnIDUIContainerController` too complex?
* Are single-use container, `close()`, and `markClosed()` understandable?
* Any WTF around cancellation when container closes?
