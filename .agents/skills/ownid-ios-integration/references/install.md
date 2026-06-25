# Install

Use this reference only to add OwnID iOS SDK v4 dependencies to a client iOS
app.

## Contents

- [Sources Of Truth](#sources-of-truth)
- [Products](#products)
- [Version And Compatibility](#version-and-compatibility)
- [Swift Package Manager](#swift-package-manager)
- [CocoaPods Compatibility Fallback](#cocoapods-compatibility-fallback)
- [Review Checks](#review-checks)

## Sources Of Truth

Before editing, check the host app's package manager, Xcode target setup,
package references, lockfiles, and approved SDK version. For new installs, use
the latest public OwnID SDK v4 release unless the user or host app policy
requires a pinned version. Verify OwnID snippets and compatibility against the
public SDK release tag for the version being integrated:

```text
https://github.com/OwnID/ownid-ios-sdk/tree/<version>
```

For CocoaPods fallback use, verify the public repository tag and the podspecs
in that tag for the same version.

Use this checkout only to understand intended v4 package metadata. Client-app
contracts come from public package metadata, public API/source comments, and
public tags. Use public docs as guidance and report stale docs when they
disagree with code or metadata.

## Products

OwnID iOS SDK v4 is distributed through Swift Package Manager. CocoaPods Trunk
does not publish the v4 pod names, and CocoaPods support is a best-effort
compatibility fallback for CocoaPods-only apps.

| App need | Add |
| --- | --- |
| Configuration, providers, Elite Flow, Headless, Passkey Enrollment, WebBridge, passkey authentication APIs, or built-in Sign in with Apple support | `OwnIDCore` |
| Boost widgets, SDK-provided SwiftUI operation UI, app-hosted SwiftUI operation UI, themes, colors, or reusable SwiftUI components | `OwnIDSwiftUI` |

`OwnIDSwiftUI` depends on `OwnIDCore`. Add `OwnIDCore` separately only when the
app target imports `OwnIDCore` directly or the project convention requires
explicit direct products.

Provider helpers are source-only examples, not SwiftPM products or pods.

## Version And Compatibility

- Use the latest public OwnID SDK v4 version for new installs unless the user,
  ticket, host app policy, or existing lockfile requires a pinned version.
- Resolve the version from public GitHub releases/tags, Swift Package
  resolution, or the host app's approved update tooling before editing files.
- Verify the selected package exists and the matching public repository tag
  exists for that version. For CocoaPods fallback use, verify the podspecs exist
  in that tag.
- Keep `OwnIDCore` and `OwnIDSwiftUI` on the same approved SDK release unless
  published metadata for that exact release says otherwise.
- Use only stable public releases unless the task explicitly approves a beta,
  release-candidate, branch, revision, local path, private source, or
  unpublished podspec channel.
- Stop and report if GitHub tags, SwiftPM resolution, and the requested version
  disagree. Treat README badges as latest-version signals only. For CocoaPods
  fallback use, also stop if the podspec version or source tag disagrees with
  the selected tag.

Compatibility gates to check before editing:

- iOS 13.0 or higher.
- Swift 6.
- Xcode 16.0 or higher.
- `OwnIDSwiftUI` requires a target that can link and use SwiftUI.
- Existing SwiftPM/CocoaPods resolution and lockfile policy.

Do not change deployment target, Swift language mode, Xcode requirement,
signing settings, package manager, workspace/project structure, or lockfiles
unless the user approves that platform/dependency work.

## Swift Package Manager

Use SwiftPM when the host app already uses SwiftPM or the task explicitly asks
for it.

```swift
dependencies: [
    .package(url: "https://github.com/OwnID/ownid-ios-sdk.git", from: "<latest-version>")
]
```

Package manifest product names:

```swift
.product(name: "OwnIDCore", package: "OwnID")
.product(name: "OwnIDSwiftUI", package: "OwnID")
```

For Xcode package references, add the package and then add only the smallest
required product to the app target. Preserve `Package.resolved` according to
the host app's lockfile policy.

## CocoaPods Compatibility Fallback

Use Swift Package Manager whenever the host app can use it. Use CocoaPods only
when the host app is CocoaPods-only or the task explicitly accepts the
best-effort compatibility fallback.

```ruby
target "YourApp" do
  pod "OwnIDCore",
    :git => "https://github.com/OwnID/ownid-ios-sdk.git",
    :tag => "<version>"
end
```

```ruby
target "YourApp" do
  pod "OwnIDCore",
    :git => "https://github.com/OwnID/ownid-ios-sdk.git",
    :tag => "<version>"

  pod "OwnIDSwiftUI",
    :git => "https://github.com/OwnID/ownid-ios-sdk.git",
    :tag => "<version>"
end
```

Declare `OwnIDCore` and `OwnIDSwiftUI` from the same exact public tag. Do not
use CocoaPods Trunk snippets such as `pod "OwnIDCore", "<version>"` for v4
unless v4 pods are later published to Trunk and public docs are updated.

## Review Checks

- The selected product matches the SDK surface the app uses.
- Version, package/pod metadata, tag, and compatibility gates were checked for
  the chosen SDK release.
- Dependency declarations follow the host app's existing package-manager style.
- No package-manager switch, broad update, or unrelated platform/dependency
  upgrade was made without approval.
