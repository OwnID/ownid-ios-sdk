# Providers

Providers are optional extensions that supply app-specific capabilities for OwnID functionality. Add only the providers that match the functionality and identity systems your app uses; you do not need to register every available provider.

Providers usually fit into these categories:

- App-owned authentication providers, such as `sessionCreate` and `passwordAuthenticate`, connect OwnID to your session and password-authentication system.
- Social sign-in capabilities connect OwnID to external social sign-in sources. Sign in with Google is registered as a provider and can use the source-only helper file. Sign in with Apple is built into `OwnIDCore` through AuthenticationServices, but still requires app and tenant setup.
- Source-only identity-platform helpers can register app-owned providers like `sessionCreate` and `passwordAuthenticate` for a specific identity platform.

## Contents

- [How Providers Work](#how-providers-work)
- [Session Create](#session-create)
- [Password Authenticate](#password-authenticate)
- [Sign in with Apple](#sign-in-with-apple)
- [Sign in with Google](#sign-in-with-google)
- [SAP Customer Data Cloud (Gigya)](#sap-customer-data-cloud-gigya)

## How Providers Work

Register providers after SDK initialization and before starting functionality that needs them. Because providers are usually shared app capabilities, such as session creation, password authentication, and social sign-in, most apps should register them on the top-level `OwnID` namespace handle, typically once during startup:

```swift
import OwnIDCore

OwnID.setProviders { registrar in
    registrar.sessionCreate { provider in
        provider.create { params in await authBackend.createSession(params) }
    }
    registrar.passwordAuthenticate { provider in
        provider.authenticate { params in await authBackend.passwordLogin(params) }
    }
}
```

Use `setProviders` to update provider bindings on the current namespace handle so OwnID functionality can share the same app-owned capabilities. Provider types declared in the block replace existing providers of the same type; other provider bindings remain unchanged.

Use `withProviders` only when one specific SDK request or session needs provider overrides without changing global behavior; it is a special-case override tool, not the default setup pattern. See [Namespace Handles](namespace-handles.md) for handle behavior.

Provider bindings are materialized when the providers block returns; do not retain the registrar or provider builders outside that block.

Provider failures are reported by the OwnID functionality that used the provider. Handle them in the result or event callback for that flow, API, or operation rather than treating provider errors as a separate global channel.

## Session Create

Use `sessionCreate` when OwnID functionality needs to create or restore your app session. The provider receives the authenticated login ID, OwnID Access Token, authentication method, and session payload; use those values at your app's session boundary.

Implement `create`; add `isAvailable` only when this provider cannot handle every request. `create` returns Swift `Result<SessionOutput, any Error & Sendable>`. The SDK requires `create` during provider registration and stops execution if it is missing.

Treat `accessToken` and `sessionPayload` as sensitive session material. OwnID invokes `create` and `isAvailable` on the main actor; keep backend work asynchronous rather than blocking the main actor. For exact parameters and return values, see [`SessionCreate`](../../OwnIDCore/Sources/Provider/SessionCreate.swift).

In these Swift examples, backend methods return `Result` with a `Sendable` error type to match the provider contract.

```swift
import OwnIDCore

OwnID.setProviders { registrar in
    registrar.sessionCreate { provider in
        provider.isAvailable { params in
            !params.loginID.id.isEmpty
        }

        provider.create { params in
            // authBackend is your app-owned auth/session layer, not an OwnID SDK object.
            await authBackend.createSession(
                loginID: params.loginID.id,
                accessToken: params.accessToken,
                sessionPayload: params.sessionPayload
            )
            .map { session in SessionOutput(session: session) }
        }
    }
}
```

## Password Authenticate

Use `passwordAuthenticate` when OwnID functionality can fall back to your app's password login. Verify passwords through your app's authentication system or identity provider; do not send passwords to OwnID.

Implement `authenticate`; add `isAvailable` only when this provider cannot handle every request. `authenticate` returns Swift `Result<SessionOutput, any Error & Sendable>`. The SDK requires `authenticate` during provider registration and stops execution if it is missing.

OwnID invokes `authenticate` and `isAvailable` on the main actor; keep backend work asynchronous rather than blocking the main actor. For exact parameters and return values, see [`PasswordAuthenticate`](../../OwnIDCore/Sources/Provider/PasswordAuthenticate.swift).

```swift
import OwnIDCore

OwnID.setProviders { registrar in
    registrar.passwordAuthenticate { provider in
        provider.authenticate { params in
            // authBackend is your app-owned auth layer, not an OwnID SDK object.
            await authBackend.passwordLogin(
                loginID: params.loginID.id,
                password: params.password
            )
            .map { session in SessionOutput(session: session) }
        }
    }
}
```

## Sign in with Apple

Sign in with Apple is a built-in iOS social sign-in capability. It is not registered through `OwnID.setProviders`, but it still requires Apple capability setup on the iOS app target and Apple Sign-in configuration in the OwnID Console. The iOS SDK uses Apple's AuthenticationServices framework for the native authorization UI.

To use it:

1. Enable **Sign in with Apple** for the app target in Xcode. See Apple's [Configuring Sign in with Apple support](https://developer.apple.com/documentation/xcode/configuring-sign-in-with-apple) guide for the Xcode capability setup.

2. Make sure the target entitlements include the [Sign in with Apple entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.applesignin):

   ```xml
   <key>com.apple.developer.applesignin</key>
   <array>
       <string>Default</string>
   </array>
   ```

3. Make sure the app's App ID in Apple Developer has the **Sign in with Apple** capability enabled and matches the app target bundle identifier.

4. If the app uses manual signing, regenerate and install provisioning profiles after changing the App ID capability.

5. Follow the [OwnID Apple Sign-in guide](https://docs.ownid.com/social-providers/apple) for Apple Sign-in configuration in the OwnID Console.

## Sign in with Google

Sign in with Google setup has two parts: app-side provider wiring in your iOS app and Google Sign-In configuration in the OwnID Console. OwnID's source-only Google provider helper connects OwnID Google sign-in to GoogleSignIn-iOS; copy it into your app target.

The Google provider implements `signIn`; it returns `SocialResult.success`, `canceled`, or `fail`. OwnID invokes `signIn`, `cancel`, and `signOut` on the main actor. For exact parameters and return values, see [`SignInWithSocial`](../../OwnIDCore/Sources/Capability/SignInWithSocial.swift).

To use it:

1. Copy [`Providers/OwnIDSignInWithGoogleProvider.swift`](../../Providers/OwnIDSignInWithGoogleProvider.swift) unchanged into the same app target that registers the provider.

2. Add [GoogleSignIn-iOS](https://github.com/google/GoogleSignIn-iOS) `9.1.0` or later to your app target dependencies. This is the minimum version this helper is documented against; newer compatible versions can be used. See Google's [iOS integration guide](https://developers.google.com/identity/sign-in/ios/start-integrating) for package setup details.

3. Register the Google iOS OAuth client's `REVERSED_CLIENT_ID` value in the app target's URL Types and forward redirect URLs to Google Sign-In. This value must come from the iOS OAuth client, not the Web OAuth client.

   ```swift
   WindowGroup {
       RootView()
           .onOpenURL { url in
               _ = GIDSignIn.sharedInstance.handle(url)
           }
   }
   ```

4. Register the copied helper with OwnID from the main actor after SDK initialization and before using functionality that needs Google sign-in. The helper requires a `configurationProvider`: configure GoogleSignIn with the app's iOS OAuth client ID and use the OwnID-provided client ID as the Google server client ID. Pass `presentingViewControllerProvider` only when the app uses a custom scene or container hierarchy.

   ```swift
   import GoogleSignIn
   import OwnIDCore

   let googleIOSClientID = "<Google iOS OAuth client ID>"

   OwnID.setProviders { registrar in
       registrar.signInWithGoogleProvider(configurationProvider: { serverClientID in
           GIDConfiguration(
               clientID: googleIOSClientID,
               serverClientID: serverClientID
           )
       })
   }
   ```

   The `serverClientID` argument is the Google Web/server client ID returned by the OwnID challenge. The `clientID` passed to `GIDConfiguration` must be the app's iOS OAuth client ID.

5. Follow the [OwnID Google Sign-In guide](https://docs.ownid.com/social-providers/google) for Google Cloud and OwnID Console configuration.

## SAP Customer Data Cloud (Gigya)

SAP Customer Data Cloud (Gigya) setup has two parts: app-side provider wiring in your iOS app and SAP Customer Data Cloud configuration for OwnID.

The source-only helper:

- Connects OwnID `sessionCreate` and `passwordAuthenticate` providers to SAP Customer Data Cloud.
- Must be copied into your app target.
- Depends on the SAP Customer Data Cloud Swift SDK version owned by the app.

The helper expects the OwnID-provided SAP Customer Data Cloud session payload shape: `sessionInfo` for successful session creation or `errorJson` for SAP Customer Data Cloud errors. Password-login cancellation is best-effort because SAP Customer Data Cloud does not expose a cancellation handle.

To use it:

1. Copy [`Providers/OwnIDGigyaProviders.swift`](../../Providers/OwnIDGigyaProviders.swift) unchanged into the same app target that registers the providers.

2. Add SAP Customer Data Cloud Swift SDK `1.7.6` or later to your app target dependencies. This is the minimum version this helper is documented against; newer compatible versions can be used. See the official [SAP/gigya-swift-sdk](https://github.com/SAP/gigya-swift-sdk) repository for SDK setup details.

3. Configure and initialize SAP Customer Data Cloud in your app before registering OwnID providers.

4. Register the copied helper with OwnID after SDK initialization and before using functionality that needs SAP Customer Data Cloud sessions or password login.

   ```swift
   import Gigya
   import OwnIDCore

   OwnID.setProviders { registrar in
       registrar.gigyaProviders(gigya: Gigya.sharedInstance())
   }
   ```

5. Follow the [OwnID SAP Customer Data Cloud guide](https://docs.ownid.com/integrations/sap-customer-data-cloud) for SAP Customer Data Cloud and OwnID Console configuration.
