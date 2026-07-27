# Install

Use this reference only to add OwnID iOS SDK v4 dependencies to a client iOS
app.

## Contents

- [Products](#products)
- [Version And Compatibility](#version-and-compatibility)
- [Swift Package Manager](#swift-package-manager)
- [CocoaPods Compatibility Fallback](#cocoapods-compatibility-fallback)
- [Review Checks](#review-checks)

## Products

OwnID iOS SDK v4 is distributed through Swift Package Manager. CocoaPods Trunk
does not publish the v4 pod names, and CocoaPods support is a best-effort
compatibility fallback for CocoaPods-only apps.

| App need | Add |
| --- | --- |
| Configuration, providers, Elite Flow, Passkey Enrollment, WebBridge, passkey authentication APIs, or built-in Sign in with Apple support | `OwnIDCore` |
| Boost widgets, SDK-provided SwiftUI operation UI, app-hosted SwiftUI operation UI, themes, colors, or reusable SwiftUI components | `OwnIDSwiftUI` |

`OwnIDSwiftUI` depends on `OwnIDCore`. Add `OwnIDCore` separately when the app
target imports `OwnIDCore` directly, names Core callback/response types, or the
project convention requires explicit direct products. This includes the
`BoostFlowCreatePasskeyResponse` state pattern in `boost-flow.md`.

Provider helpers are maintained source-only integration files copied into the
app target; they are not SwiftPM products or pods.

## Version And Compatibility

For a new install, use the latest stable public OwnID SDK v4 release unless the
user, task, host policy, lockfile, or existing integration pins another version.
Preserve an approved existing version unless the task requests an upgrade.
Verify the selected package against the matching public repository tag; for a
CocoaPods fallback, verify the podspecs in that tag.

- Check the release's documented compatibility before changing dependencies.
- Keep `OwnIDCore` and `OwnIDSwiftUI` on the same approved SDK release unless
  published metadata for that exact release says otherwise.

Compatibility gates to check before editing:

- iOS 13.0 or higher.
- Xcode 16.0 or higher with a Swift 6-capable toolchain. The SDK package uses
  Swift 6 mode; consuming it does not by itself require changing the host app
  target's Swift language mode.
- `OwnIDSwiftUI` requires a target that can link and use SwiftUI.
- Existing SwiftPM/CocoaPods resolution and lockfile policy.

Keep deployment target, Swift language mode, Xcode requirement, signing,
package manager, workspace/project structure, and lockfile policy aligned with
the host app. Treat any required baseline change as separate platform work.

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

Declare `OwnIDCore` and `OwnIDSwiftUI` from the same exact release tag. Use the
git-tag form above when the selected v4 release metadata provides the pods
through git; use a CocoaPods Trunk declaration when that release metadata shows
the v4 pods there.

## Review Checks

- The selected product matches the SDK surface the app uses.
- Version, package/pod metadata, tag, and compatibility gates were checked for
  the chosen SDK release.
- Dependency declarations follow the host app's existing package-manager style.
- Package-manager choice, lockfile updates, and any required platform upgrade
  match the agreed integration scope.
