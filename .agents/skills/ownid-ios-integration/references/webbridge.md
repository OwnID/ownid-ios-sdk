# WebBridge

Use this reference when integrating OwnID SDK v4 WebBridge into an iOS app-owned
`WKWebView`.

Full public docs: `../../../../docs/integration/webbridge.md`.

## Contents

- [Scope](#scope)
- [Before Editing](#before-editing)
- [Providers And Context](#providers-and-context)
- [Origins And Attachment](#origins-and-attachment)
- [Implementation Pattern](#implementation-pattern)
- [Plugins And Lifecycle](#plugins-and-lifecycle)
- [Validation](#validation)

## Scope

WebBridge is for an app-owned `WKWebView` that loads an app/tenant page where
the OwnID Web SDK is initialized. The app owns the `WKWebView`, lifecycle, page
URL, trusted origins, and web content. The native SDK supplies the bridge so
that page can call selected native SDK capabilities.

Use WebBridge only when the page needs native OwnID SDK capabilities such as
passkeys, stored user, scoped context, Sign in with Apple, Google sign-in,
`sessionCreate`, or `passwordAuthenticate`.

Add `OwnIDCore` and complete iOS passkey prerequisites. WebBridge has no
WebBridge-specific plist entry, target capability, URL scheme, or service
setup. Sign in with Apple and passkeys have their own Apple entitlement
requirements.

## Before Editing

Collect:

- SDK initialization location;
- app-owned `WKWebView` instance and the object that owns its lifecycle;
- page URL and trusted origins;
- whether server-provided `webView.allowedOrigins` is enough or explicit
  `allowedOriginRules` are needed;
- WebBridge capabilities used by the page;
- existing passkey, provider, and Apple capability setup.

Stop and ask before guessing trusted origins, relying-party domains,
social-provider setup, backend session contracts, or wildcard-origin policy.

## Providers And Context

Register providers globally with `OwnID.setProviders` for provider-backed
capabilities the page can call. Use scoped `withProviders` only when this
`WKWebView` session intentionally needs behavior different from global
providers.

Put session-local auth input in `withContext` before `OwnID.webBridge.create()`.
Changing context or providers after bridge creation does not update that
bridge.

Sign in with Apple is built into `OwnIDCore` and is enabled through
Apple/tenant setup. Google uses the source-only provider helper or a custom
`signInWithGoogle` provider.

Use the public WebBridge docs for the capability table and origin rules. Use
the providers, context, and namespace-handle references for their detailed
contracts.

## Origins And Attachment

Attach only to reviewed trusted origins. Pass explicit `allowedOriginRules`
when server config may not be available yet or when the session needs a
local/tenant-specific trusted origin. Treat `*` as a production security-review
decision.

Attach before `load(...)`; reload the page after a successful attach if it was
already loaded. `attach(...)` and `detach()` are main-actor calls from the UI
owner that controls the `WKWebView`.

Configure the trusted-page `WKWebView` so the OwnID Web SDK JavaScript can
run, while keeping the host app's normal web view hardening in place.

`attach(...)` returns `nil` on success and `WebBridgeError` on failure. Handle
attachment failure before loading a page that requires native bridge
capabilities.

## Implementation Pattern

```swift
let bridge = OwnID.webBridge
    .withContext { context in
        context.authz = .fromToken(accessToken)
        context.accountDisplayName = displayName
    }
    .create()

let error = bridge.attach(
    webView: webView,
    allowedOriginRules: ["https://login.example.com"]
)

if error == nil {
    webView.load(URLRequest(url: URL(string: "https://login.example.com")!))
} else {
    // Map the bridge attachment failure to app diagnostics or fallback UI.
}
```

Omit `withContext` when the page does not need scoped auth/context input. If
server-provided origins are sufficient and available, `bridge.attach(webView:)`
is also valid.

## Plugins And Lifecycle

Most apps use the default plugin set. Add or remove per-bridge custom plugins
through `bridge.plugins` only before `attach(...)`, and use fresh plugin
instances per bridge. Change `OwnID.webBridge.defaultPluginFactories` only
before `create()` for future bridges.

Create one fresh bridge per `WKWebView` session. Keep a strong reference while
the page is active. Detach when the session ends.

Detaching does not remove `WKUserScript` entries already added to the
`WKUserContentController`; use a new `WKWebView`/configuration when the next
session needs a clean content controller.

Checked-in iOS demos currently have no app-owned WebBridge example. Use public
API comments and source as the contract; use public docs as guidance.

## Validation

- OwnID initializes before bridge creation.
- The trusted page loads OwnID Web SDK.
- `attach(...)` succeeds for the intended origin before page load or after
  reload.
- Attachment failure uses an app fallback before loading a page that requires
  the bridge.
- Capabilities used by the page work with the active scope.
- Session teardown detaches the bridge and a new `WKWebView` session creates a
  new bridge.
