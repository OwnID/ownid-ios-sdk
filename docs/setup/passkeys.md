# Passkey Setup

OwnID uses Apple's [AuthenticationServices](https://developer.apple.com/documentation/authenticationservices) framework for passkey creation and authentication. Platform passkeys work on iOS 16 and higher.

## Associated Domains

Passkeys require your app and relying party domain to be associated with Apple's `webcredentials` service.

Use the same relying party domain that OwnID uses for passkey requests.

For the app target, add the **Associated Domains** capability in its signing and capabilities settings, then add:

```text
webcredentials:<relying-party-domain>
```

Use the exact relying party host without `https://`, a path, query parameters, or a trailing slash.

Host an Apple App Site Association file at:

```text
https://<relying-party-domain>/.well-known/apple-app-site-association
```

The file must be publicly available over HTTPS, return `HTTP 200`, use a JSON content type, avoid redirects, stay under 128 KB, and have no `.json` extension.

```json
{
  "webcredentials": {
    "apps": [
      "<APP_ID_PREFIX>.<BUNDLE_ID>"
    ]
  }
}
```

Add each app target that should use passkeys as `<APP_ID_PREFIX>.<BUNDLE_ID>`. This value must match the signed app's `application-identifier` entitlement. The App ID prefix is usually the Apple Team ID; if it differs, use the prefix from the signed app or provisioning profile.

See Apple's [Supporting associated domains](https://developer.apple.com/documentation/xcode/supporting-associated-domains) and [Associated Domains Entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.associated-domains) for the platform requirements and validation behavior.

## Verify the Association

> [!WARNING]
> The association file must be publicly accessible in every environment where passkeys are tested or used. The endpoint must not require a password, Basic Auth, SSO, cookies, VPN access, mTLS, an IP allowlist, or an interactive WAF or bot-protection challenge.

Verify the association file on the exact HTTPS host used as the relying party domain:

```text
https://<relying-party-domain>/.well-known/apple-app-site-association
```

Confirm that the endpoint:

- Returns `HTTP 200` with a JSON content type
- Does not redirect
- Returns valid JSON rather than an HTML login or error page
- Is accessible from a public network without authentication or VPN access
- Is accessible regardless of client IP address, region, or User-Agent

Verify the Associated Domains capability for the app target:

1. Open the target's signing and capabilities settings and find **Associated Domains**. Add the capability if it is missing.
2. Confirm that the domain list contains the exact relying party host as `webcredentials:<relying-party-domain>`, without `https://`, a path, query parameters, or a trailing slash.
3. Confirm that the same host is used for the passkey relying party domain and the `apple-app-site-association` URL.
4. Confirm that `webcredentials.apps` contains the app's exact `<APP_ID_PREFIX>.<BUNDLE_ID>` value.

## Allow Time for Updates

The association file may be cached by your hosting provider, CDN, and Apple verification services. Updating the origin file does not guarantee that devices receive the new version immediately.

Inspect the response headers:

```bash
curl -sS -D - -o /dev/null \
  https://<relying-party-domain>/.well-known/apple-app-site-association
```

Review `Cache-Control`, `Age`, `Expires`, `ETag`, and `Last-Modified`. Avoid long cache lifetimes, such as one week, if you expect to update the file. A long `max-age` can keep an earlier version valid after the origin file has changed.

Apple's CDN normally requests the `apple-app-site-association` file within 24 hours. Devices check for updates approximately once per week after installation, and Apple does not provide manual cache invalidation. See [Supporting associated domains](https://developer.apple.com/documentation/xcode/supporting-associated-domains).

After an update, first confirm that the public endpoint returns the new file and review its current cache headers.
