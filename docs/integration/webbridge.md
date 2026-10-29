# WebBridge

[`WebBridge`](../../OwnIDCore/Sources/UI/WebBridge/WebBridge.swift) connects the OwnID Web SDK running in an app-owned `WKWebView` to native OwnID iOS SDK capabilities. Use it when your app hosts OwnID-enabled web authentication pages and the page needs native passkeys, stored user data, social sign-in, scoped SDK context, or app-owned [authentication providers](../setup/providers.md).

## Contents

- [Minimal Integration](#minimal-integration)
- [Prerequisites](#prerequisites)
- [Configuration Checklist](#configuration-checklist)
- [Attach and Lifecycle](#attach-and-lifecycle)
- [Allowed Origins](#allowed-origins)
- [Plugins](#plugins)
- [Runtime Errors](#runtime-errors)

## Minimal Integration

Create a fresh bridge for each `WKWebView` session, attach it to trusted origins before loading the page, then load the OwnID-enabled web page.

```swift
import OwnIDCore
import UIKit
import WebKit

final class LoginWebViewController: UIViewController {
    private let webView = WKWebView()
    private var bridge: (any WebBridge)?

    override func viewDidLoad() {
        super.viewDidLoad()

        let bridge = OwnID.webBridge.create()
        let error = bridge.attach(
            webView: webView,
            allowedOriginRules: ["https://login.example.com"]
        )

        guard error == nil else {
            // Map the bridge attachment failure to app diagnostics or an app-owned recovery path.
            return
        }

        self.bridge = bridge
        webView.load(URLRequest(url: URL(string: "https://login.example.com")!))
    }

    deinit {
        bridge?.detach()
    }
}
```

`attach(...)` returns `nil` on success and [`WebBridgeError`](../../OwnIDCore/Sources/UI/WebBridge/WebBridge.swift) on failure. If an attach attempt fails, correct the cause and retry with the same bridge. After an attach succeeds, that bridge is single-use: `detach()` does not make it attachable again, so create a new `WebBridge` for each new `WKWebView` session.

## Prerequisites

- Add the Core SDK as described in [Install](../../README.md#install), initialize OwnID in [Configuration](../setup/configuration.md), and complete platform passkey setup in [Passkey Setup](../setup/passkeys.md).
- Use an app-owned `WKWebView` that loads a trusted app/tenant page with the OwnID Web SDK.
- Provide at least one valid trusted origin through server configuration, explicit `allowedOriginRules`, or both. If the first bridged page must work before server configuration is available, pass the required origins explicitly.

## Configuration Checklist

WebBridge attaches native SDK capabilities to an app-owned web session. Configure namespace context, providers, and default plugin factories before creating the bridge. Configure that bridge's plugins before attaching it. Changes after those points do not update the active web session. At attachment, the bridge combines explicit origin rules with the latest available server configuration.

| Area | Required when | Details |
| --- | --- | --- |
| Web view session | Always. | Use an app-owned `WKWebView`, create one bridge per session, retain it while active, and attach before loading the trusted page. See [Attach and Lifecycle](#attach-and-lifecycle). |
| Allowed origins | Always. | Provide trusted origins through server configuration, explicit `allowedOriginRules`, or both. See [Allowed Origins](#allowed-origins). |
| Passkeys | The hosted page uses passkey web actions. | Complete [platform passkey setup](../setup/passkeys.md). |
| Stored user | The hosted page uses stored-user web actions. | Built-in SDK capability; no app setup required. |
| Context | The hosted page requests native context. | Set context before bridge creation. See [Context](../setup/context.md) and [Namespace Handles](../setup/namespace-handles.md). |
| Sign in with Apple | The hosted page uses Sign in with Apple. | Set up [Sign in with Apple](../setup/providers.md#sign-in-with-apple) for the app target and OwnID Console. |
| Sign in with Google | The hosted page uses Sign in with Google. | Register [`googleSignIn`](../setup/providers.md#sign-in-with-google). |
| Session creation | The hosted page requests app session creation. | Register [`sessionCreate`](../setup/providers.md#session-create). |
| Password authentication | The hosted page uses password authentication. | Register [`passwordAuthenticate`](../setup/providers.md#password-authenticate). |

Provider-backed web actions use app-owned provider capabilities from the SDK scope used to create the bridge. Normally register providers globally during startup with `OwnID.setProviders` before creating the bridge. Use `withProviders` only for a WebBridge session that needs different provider bindings; changes to a parent scope after bridge creation do not update that bridge. See [Providers](../setup/providers.md).

For a direct app-owned WebBridge, the attached `WKWebView` is the UI owner; a separately registered `uiContext` provider does not replace that bridge-local presentation context. [Elite Flow](../flows/elite-flow.md) is different because the SDK owns its WebView presentation.

Set session-specific auth input close to the bridge with `withContext`:

```swift
let bridge = OwnID.webBridge
    .withContext { context in
        context.authz = .fromToken(accessToken)
    }
    .create()
```

## Attach and Lifecycle

Create a fresh bridge for each app-owned `WKWebView` session. Configure providers, context, and default plugin factories before `create()`. Configure bridge-specific plugins through `bridge.plugins` before `attach(...)`.

Attach the bridge before loading the trusted page. `attach(...)` returns `nil` on success and the attachment failure as `WebBridgeError` otherwise. A failed attach does not consume the bridge, so the same instance can be retried after the cause is corrected. A successful attach consumes the bridge permanently; a later attach, including after `detach()`, fails and requires a new bridge.

`attach(...)` must run on the main actor. Retain the bridge while the `WKWebView` session is active, and call `detach()` when the web view is dismissed or no longer used.

WebKit does not scope document-start user scripts to origins. WebBridge validates the source origin and accepts messages only from the allowed main frame before invoking native plugins; messages from subframes or untrusted origins are rejected.

`detach()` removes native message handlers and cancels pending native work, but it does not remove `WKUserScript` entries already installed in the web view's `WKUserContentController`. Those scripts cannot reach native handlers after detach. Use a fresh `WKWebView` or configuration when the next session requires a clean script list.

Passkey and social requests are presented from the exact window belonging to the attached `WKWebView`. If that WebView is no longer attached to a window, the request returns a bridge error without invoking the native capability.

## Allowed Origins

Allowed origins define which hosted pages can use the native bridge. During `attach(webView:allowedOriginRules:)`, the SDK builds the effective allowlist from explicit `allowedOriginRules` and the latest available server configuration `webView.allowedOrigins`, normalizes the combined set, and applies it to bridge policy and message handling.

Attachment uses server origins already available to that bridge; it does not fetch or wait for configuration. A successful attachment keeps its effective allowlist for that session, so later configuration changes do not update it. Pass explicit rules when the first attachment must be deterministic.

> [!WARNING]
> Attach WebBridge only to trusted origins that you control. Avoid `*` in production unless your security review explicitly approves it.

When server configuration already contains every trusted origin for the `WKWebView`, call `attach(webView:)` without explicit `allowedOriginRules`. Pass explicit `allowedOriginRules` when the first bridged page must work before server configuration is available, or when the app needs trusted local, staging, or environment-specific origins for that session.

Origin rule handling:

- Explicit rules and server-provided rules are merged before normalization.
- Invalid rules are skipped and logged.
- Attachment fails when no valid rule remains after normalization.
- Only `http` and `https` origins are accepted; custom schemes are rejected.
- Rules must describe origins, not full page URLs. Do not include paths, query strings, fragments, or user info.
- Missing scheme defaults to `https`.
- DNS wildcard rules are supported only as a leftmost subdomain wildcard, for example `https://*.example.com`; they do not match the bare `example.com` host.
- IPv4 literals and bracketed IPv6 literals are supported. Wildcards for IP hosts are rejected.
- `*` allows any origin and should be avoided outside explicitly reviewed cases.

| Rule | Normalized as | Notes |
| --- | --- | --- |
| `https://login.example.com` | `https://login.example.com` | Recommended production form. |
| `http://localhost:3000` | `http://localhost:3000` | Use only for local or trusted non-production environments. |
| `login.example.com` | `https://login.example.com` | Missing scheme defaults to `https`. |
| `https://login.example.com:8443` | `https://login.example.com:8443` | Explicit ports must be in `1...65535`. |
| `https://*.example.com` | `https://*.example.com` | Matches DNS subdomains only; does not match `example.com`. |
| `127.0.0.1` | `https://127.0.0.1` | IPv4 literals are supported. |
| `[2001:db8::1]` | `https://[2001:db8::1]` | IPv6 literals must be bracketed. |
| `*` | `*` | Allows any origin. Avoid in production. |

## Plugins

Most apps should use the default plugin set. Built-in plugins back the WebBridge capabilities listed in [Configuration Checklist](#configuration-checklist).

Customize plugins only when the hosted page and app define an additional [`WebBridgePlugin`](../../OwnIDCore/Sources/UI/WebBridge/WebBridgePlugin.swift) namespace/action contract.

### Per-Bridge Plugins

Use [`bridge.plugins`](../../OwnIDCore/Sources/UI/WebBridge/WebBridgePluginRegistry.swift) when only one `WKWebView` session needs a custom plugin. Add, replace, or remove plugins before `attach(...)`; the bridge snapshots this registry during attachment.

Register a fresh plugin instance for each bridge. A plugin with the same key replaces the previous plugin for that key.

### Default Plugins

Use [`OwnID.webBridge.defaultPluginFactories`](../../OwnIDCore/Sources/UI/WebBridge/WebBridgePluginFactoryStore.swift) only when future bridges from that namespace should receive the same plugin change. Update default factories before `create()`; an already created bridge is changed through `bridge.plugins`.

Each factory must create a fresh plugin instance for each bridge.

## Runtime Errors

After a successful attach, WebBridge sends native capability results back to the hosted page. Expected runtime outcomes are reported through the hosted-page WebBridge contract when the incoming request can be handled safely. Invalid, untrusted, or incomplete requests are rejected by the bridge and should be treated as integration diagnostics.

Use an app-owned recovery path when the bridge cannot attach, when a request is rejected because its origin/frame/payload is not trusted or valid, or when the app intentionally exits the `WKWebView` flow before loading the bridged page. Treat cancellation after `detach()` as a normal session-ending outcome and make page-side requests tolerant of a missing callback.
