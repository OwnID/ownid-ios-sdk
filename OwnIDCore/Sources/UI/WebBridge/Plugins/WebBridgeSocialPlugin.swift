import Foundation
import UIKit

/// Built-in SOCIAL plugin backed by configured social sign-in providers.
///
/// This is an internal WebBridge contract for hosted pages, not a stable app-developer API. Injection metadata advertises
/// only provider actions available to this bridge. This implementation exposes `Apple` and `Google` actions when the
/// matching providers are registered.
///
/// The hosted page must supply `clientId` and `challengeId`. The plugin forwards them as ``SocialSignInParams``,
/// checks provider availability, then starts provider sign-in using the attached WebView's presentation context.
/// Success returns the provider ID token as the WebBridge success payload. Provider cancellation maps to bridge error
/// type `ABORTED`; missing provider support, unavailable providers, invalid parameters, missing presentation context,
/// and provider failures return bridge error messages.
internal actor WebBridgeSocialPlugin: WebBridgePlugin {
    internal static let KEY = WebBridgePluginKey(id: "SOCIAL")

    nonisolated var key: WebBridgePluginKey { Self.KEY }
    nonisolated let actions: [String]

    private let appleSignIn: (any AppleSignInProvider)?
    private let googleSignIn: (any GoogleSignInProvider)?
    private let uiContextProvider: any UIContextProvider
    private let coder: any JSONCoder
    private let logger: OwnIDLogRouter?

    init(
        appleSignIn: (any AppleSignInProvider)?,
        googleSignIn: (any GoogleSignInProvider)?,
        uiContextProvider: any UIContextProvider,
        coder: any JSONCoder,
        logger: OwnIDLogRouter?
    ) {
        self.appleSignIn = appleSignIn
        self.googleSignIn = googleSignIn
        self.uiContextProvider = uiContextProvider
        self.coder = coder
        self.logger = logger

        var availableActions: [String] = []
        if appleSignIn != nil { availableActions.append("Apple") }
        if googleSignIn != nil { availableActions.append("Google") }
        self.actions = availableActions
    }

    nonisolated func handle(_ message: WebBridgePluginMessage) async -> WebBridgePluginResult {
        await handleIsolated(message)
    }

    private func handleIsolated(_ message: WebBridgePluginMessage) async -> WebBridgePluginResult {
        guard key.id.caseInsensitiveCompare(message.payload.pluginID) == .orderedSame else {
            return WebBridgePluginResult.error(message: "WebBridgeSocialPlugin: Wrong plugin ID: \(message.payload.pluginID)")
        }

        switch message.payload.action.uppercased() {
        case "APPLE":
            guard let appleSignIn = appleSignIn else {
                return WebBridgePluginResult.error(message: "WebBridgeSocialPlugin: Sign in with Apple is not supported")
            }
            return await runSocialFlow(appleSignIn, providerName: "Apple", message: message)

        case "GOOGLE":
            guard let googleSignIn = googleSignIn else {
                return WebBridgePluginResult.error(message: "WebBridgeSocialPlugin: Sign in with Google is not supported")
            }
            return await runSocialFlow(googleSignIn, providerName: "Google", message: message)

        default:
            return WebBridgePluginResult.error(message: "WebBridgeSocialPlugin: Unknown action: \(message.payload.action)")
        }
    }

    private func runSocialFlow(_ signIn: any SocialSignIn, providerName: String, message: WebBridgePluginMessage) async
        -> WebBridgePluginResult
    {
        // Keep this payload shape aligned with the hosted-page SOCIAL action contract.
        struct Params: Decodable {
            let challengeId: String
            let clientId: String
        }

        let params: Params
        do {
            params = try coder.decodeFromString(message.payload.params ?? "{}", as: Params.self)
        } catch {
            return WebBridgePluginResult.error(message: "WebBridgeSocialPlugin: Invalid JSON: \(error.localizedDescription)")
        }

        let challengeID = ChallengeID(params.challengeId.trimmingCharacters(in: .whitespacesAndNewlines))
        let clientID = params.clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !challengeID.value.isEmpty else {
            return WebBridgePluginResult.error(message: "WebBridgeSocialPlugin: 'challengeId' is required")
        }
        guard !clientID.isEmpty else {
            return WebBridgePluginResult.error(message: "WebBridgeSocialPlugin: 'clientId' is required")
        }

        let providerParams = SocialSignInParams(clientID: clientID, nonce: challengeID.value)
        guard await signIn.isAvailable(params: providerParams) else {
            return WebBridgePluginResult.error(message: "WebBridgeSocialPlugin: Sign in with \(providerName) is unavailable")
        }

        return await Self.performSignIn(signIn, params: providerParams, uiContextProvider: uiContextProvider, logger: logger)
    }

    @MainActor
    private final class SocialInvocationCancellationGate {
        private var isActive = false

        func begin() {
            isActive = true
        }

        func finish() {
            isActive = false
        }

        func cancelIfActive(_ signIn: any SocialSignIn) {
            guard isActive else { return }
            isActive = false
            signIn.cancel()
        }
    }

    @MainActor
    private static func performSignIn(
        _ signIn: any SocialSignIn,
        params: SocialSignInParams,
        uiContextProvider: any UIContextProvider,
        logger: OwnIDLogRouter?
    ) async -> WebBridgePluginResult {
        let window: UIWindow
        do {
            window = try uiContextProvider.current().requireWindow()
        } catch {
            logger?.logW(source: Self.self, prefix: #function, message: "UI context resolution failed", cause: error)
            return WebBridgePluginResult.error(
                message: "WebBridgeSocialPlugin: Cannot resolve a presentation window: \(error.localizedDescription)"
            )
        }

        let cancellationGate = SocialInvocationCancellationGate()
        let result: SocialSignInResult? = await withTaskCancellationHandler {
            guard !Task.isCancelled else { return nil }
            cancellationGate.begin()
            defer { cancellationGate.finish() }
            return await signIn.signIn(window: window, params: params)
        } onCancel: {
            Task { @MainActor in
                cancellationGate.cancelIfActive(signIn)
            }
        }

        guard let result else {
            return WebBridgePluginResult.error(message: "WebBridgeSocialPlugin: Canceled", type: "ABORTED")
        }

        switch result {
        case .success(_, let idToken):
            return WebBridgePluginResult.success(JSONValue(idToken))

        case .canceled(let reason):
            return WebBridgePluginResult.error(message: "WebBridgeSocialPlugin: Canceled: \(reason)", type: "ABORTED")

        case .fail(let error):
            return WebBridgePluginResult.error(message: "WebBridgeSocialPlugin: \(error.errorDescription ?? "Error")")
        }
    }
}

extension WebBridgeSocialPlugin {
    internal static func create(resolver: any DIContainerResolver) throws -> WebBridgeSocialPlugin {
        WebBridgeSocialPlugin(
            appleSignIn: resolver.getOrNil(type: (any AppleSignInProvider).self),
            googleSignIn: resolver.getOrNil(type: (any GoogleSignInProvider).self),
            uiContextProvider: try resolver.getOrThrow(type: (any UIContextProvider).self),
            coder: try resolver.getOrThrow(type: (any JSONCoder).self),
            logger: resolver.getOrNil(type: OwnIDLogRouter.self)
        )
    }
}
