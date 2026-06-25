# Enable Passkeys

Use this reference for every iOS host app that integrates OwnID SDK v4. It
covers iOS passkey prerequisites: target capabilities, entitlements, app
identifiers, Apple App Site Association hosting, signing, and platform
availability.

Source docs:

- `../../../../README.md#enable-passkeys`

Platform source of truth:

- AuthenticationServices:
  `https://developer.apple.com/documentation/authenticationservices`
- Supporting associated domains:
  `https://developer.apple.com/documentation/xcode/supporting-associated-domains`
- Associated Domains entitlement:
  `https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.associated-domains`

## Contents

- [Baseline Requirement](#baseline-requirement)
- [Inputs To Collect First](#inputs-to-collect-first)
- [Host App Changes](#host-app-changes)
- [Apple App Site Association](#apple-app-site-association)
- [AuthenticationServices Reality](#authenticationservices-reality)
- [What To Verify Externally](#what-to-verify-externally)

## Baseline Requirement

Complete iOS passkey setup as baseline SDK integration work, independent of the
first OwnID feature or UI surface being integrated. Every integration needs a
known relying-party domain association plan.

## Inputs To Collect First

Confirm these values from the host app, OwnID tenant configuration, Apple
Developer account, and signing owner:

- OwnID `appID`, environment (`.prod` by default, `.uat` only when specified),
  and region used by the app.
- Relying-party domain used by OwnID passkey requests for that tenant.
- Final bundle identifier for each app target/configuration that should use
  passkeys, including production, UAT, white-label, or extension-like targets
  if they run auth.
- App ID prefix for the App ID that signs each target. This prefix is usually
  the Apple Team ID. If it differs, use the prefix from the signed
  `application-identifier` entitlement or provisioning profile.
- The entitlements file used by each app target and any `.xcconfig` variable
  that feeds associated domains.
- Whether signing is automatic or manual. Manual signing usually requires
  regenerated provisioning profiles after capability changes.

The relying-party domain is the domain in the passkey challenge. It is not
automatically the OwnID `appID`, API `rootURL`, API host, or marketing
website. Ask the tenant/backend owner when it is not explicit.

## Host App Changes

Add the Associated Domains capability to the app target that owns the OwnID SDK
integration. The signed app must contain this entitlement:

```xml
<key>com.apple.developer.associated-domains</key>
<array>
    <string>webcredentials:<relying-party-domain></string>
</array>
```

If the project uses `.xcconfig` variables, keep that style. For example, the
checked-in demos use an entitlements file with `$(ASSOCIATED_DOMAINS)` and set
the value in environment-specific `.xcconfig` files:

```text
ASSOCIATED_DOMAINS = webcredentials:<relying-party-domain>
```

Place `webcredentials:` in target entitlements through the Associated Domains
capability, not in `Info.plist`. Also enable Associated Domains for the
matching App ID in Apple Developer. With manual signing, regenerate and install
provisioning profiles before expecting the entitlement to appear in a signed
build.

No extra iOS package dependency is required for passkeys beyond OwnID SDK v4.
OwnID uses Apple's AuthenticationServices framework. The SDK products support
iOS 13+, but platform passkeys require iOS 16 or higher. Check availability
before presenting passkey actions.

## Apple App Site Association

The relying-party domain must host an Apple App Site Association file:

```text
https://<relying-party-domain>/.well-known/apple-app-site-association
```

Generate the AASA content from the values collected in intake and give the
developer the exact file content plus the required hosting path. Mark hosting
as external unless the repo or deployment system owns that host.

Minimum shape for passkeys:

```json
{
  "webcredentials": {
    "apps": [
      "<APP_ID_PREFIX>.<BUNDLE_ID>"
    ]
  }
}
```

Add every app identity that uses passkeys as `<APP_ID_PREFIX>.<BUNDLE_ID>`.
Include each environment or white-label target whose bundle identifier differs.

The file must be public over HTTPS, return HTTP 200, use a JSON content type,
avoid redirects, stay under 128 KB, and have no `.json` extension. The app
identifier in the file must match the signed app's `application-identifier`
entitlement. A UAT bundle entry does not validate a production bundle, and a
production entry does not validate a UAT bundle with a different ID.

When multiple targets share the relying-party domain, use one
`webcredentials.apps` array containing each `<APP_ID_PREFIX>.<BUNDLE_ID>`. If
the App ID prefix or final bundle ID is missing, ask for it instead of leaving
an ambiguous entry.

Treat domain hosting, Apple Developer configuration, provisioning profiles,
signing, and OwnID Console settings as explicit external work. If the app
repository cannot own the hosted AASA file, report the required external change.

## AuthenticationServices Reality

OwnID passkey operations delegate creation and authentication to Apple's
AuthenticationServices framework. Treat these as platform outcomes, not
SDK-internal states:

- Devices below iOS 16 cannot run platform passkeys.
- A device can be iOS 16+ and still fail availability because the entitlement,
  provisioning profile, AASA file, domain association, tenant config, or
  available credentials are not ready.
- Apple may fetch associated-domain files through its associated-domains CDN,
  so remote file changes may not be reflected instantly on a device.
- Users can close platform UI or have no applicable credentials.
- Availability diagnostics are for integration logs, not raw end-user copy.

Use SDK or platform availability signals before presenting passkey actions.
When availability fails, report the passkey readiness gap in the integration
work and handle the user-facing outcome in the feature that invokes passkeys.
This reference does not define session handling or app authentication behavior.

## What To Verify Externally

For each app identity/environment that should support passkeys, verify:

- OwnID tenant passkey relying-party domain is known and matches the
  `webcredentials:` domain.
- The app target has Associated Domains enabled.
- The target entitlements include
  `com.apple.developer.associated-domains` with
  `webcredentials:<relying-party-domain>`.
- Apple Developer App ID and provisioning profile allow the same Associated
  Domains entitlement.
- `https://<relying-party-domain>/.well-known/apple-app-site-association` is
  reachable as public HTTPS with HTTP 200, JSON content type, no redirect, no
  `.json` extension, and size under 128 KB.
- The AASA `webcredentials.apps` entry equals the signed app's
  `application-identifier`, normally
  `<APP_ID_PREFIX>.<BUNDLE_ID>`.
- The generated AASA content has been handed off or committed only to the
  repository/location that owns the relying-party domain.
- The integration has an explicit handling plan for unavailable, canceled,
  no-credential, and error outcomes where passkeys are invoked.

Demo note: the checked-in iOS demos show the expected pattern with
`com.apple.developer.associated-domains` in entitlements and
`ASSOCIATED_DOMAINS` supplied from `.xcconfig`. Treat demos as examples, not the
tenant contract.
