import Foundation
import Security

/// Built-in FIDO plugin backed by the platform passkey capability.
///
/// This is an internal WebBridge contract for hosted pages, not a stable app-developer API. It exposes availability,
/// assertion, and creation actions under the `FIDO` namespace. `get` expects a hosted-page challenge context and
/// relying-party ID, optionally limited by `credsIds` or `credId`, then calls ``PasskeyProtocol/getCredential``. `create`
/// accepts either the OwnID flow shape, selected by the presence of `context`, or the WebAuthn enrollment-options shape,
/// then calls ``PasskeyProtocol/createCredential``. Presentation anchoring is owned by the passkey capability; this
/// plugin does not derive a window from the WebBridge message.
///
/// Successful assertions return authenticator data, client data, signature, user handle, optional authenticator
/// attachment, and credential ID. Successful creation returns the compact OwnID flow payload or the WebAuthn-style
/// enrollment payload. User or system cancellation maps to bridge error type `ABORTED`; missing assertion credentials
/// map to `TYPE_NO_CREDENTIAL`; malformed parameters and other provider failures return bridge error messages. The
/// plugin returns WebBridge payloads only and does not persist assertion or attestation results.
@available(iOS 16.0, *)
internal actor WebBridgePasskeyPlugin: WebBridgePlugin {
    internal static let KEY = WebBridgePluginKey(id: "FIDO")

    nonisolated var key: WebBridgePluginKey { Self.KEY }
    nonisolated let actions: [String] = ["isAvailable", "create", "get"]

    private let passkey: any PasskeyProtocol
    private let localInfo: any LocalInfo
    private let coder: any JSONCoder

    private let defaultTimeoutMs = Timeout(milliseconds: 2 * 60 * 1000)

    init(passkey: any PasskeyProtocol, localInfo: any LocalInfo, coder: any JSONCoder) {
        self.passkey = passkey
        self.localInfo = localInfo
        self.coder = coder
    }

    nonisolated func handle(_ message: WebBridgePluginMessage) async -> WebBridgePluginResult {
        await handleIsolated(message)
    }

    private func handleIsolated(_ message: WebBridgePluginMessage) async -> WebBridgePluginResult {
        guard key.id.caseInsensitiveCompare(message.payload.pluginID) == .orderedSame else {
            return errorResult("WebBridgePasskeyPlugin: Wrong plugin ID: \(message.payload.pluginID)")
        }

        switch message.payload.action.uppercased() {
        case "ISAVAILABLE": return WebBridgePluginResult.success(JSONValue(localInfo.isSystemFidoCapable))
        case "GET": return await handleGet(message)
        case "CREATE": return await handleCreate(message)
        default: return errorResult("WebBridgePasskeyPlugin: Unknown action: \(message.payload.action)")
        }
    }

    private func handleGet(_ message: WebBridgePluginMessage) async -> WebBridgePluginResult {
        struct GetParams: Decodable {
            let context: String
            let relyingPartyId: String
            let credsIds: [String]?  // optional list of allowed credentials
            let credId: String?  // or single credential id
        }

        let params: GetParams
        do {
            params = try coder.decodeFromString(message.payload.params ?? "{}", as: GetParams.self)
        } catch {
            return errorResult("WebBridgePasskeyPlugin.handleGet: Invalid JSON: \(error.localizedDescription)")
        }

        let context = params.context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !context.isEmpty else {
            return errorResult("WebBridgePasskeyPlugin.handleGet: 'context' cannot be empty")
        }
        let rpId = params.relyingPartyId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rpId.isEmpty else {
            return errorResult("WebBridgePasskeyPlugin.handleGet: 'relyingPartyId' cannot be empty")
        }

        let allowIds = credentialIds(credsIds: params.credsIds, credId: params.credId)
        guard let challengeB64 = context.data(using: .utf8)?.encodeToBase64UrlSafe() else {
            return errorResult("WebBridgePasskeyPlugin.handleGet: Invalid UTF-8 in 'context')")
        }

        let assertionOptions = AssertionOptions(
            challenge: ChallengeID(challengeB64),
            rpID: rpId,
            allowCredentials: allowIds.isEmpty ? nil : allowIds.map { PublicKeyCredentialDescriptor(id: $0, type: .publicKey) },
            userVerification: .required,
            timeout: defaultTimeoutMs
        )

        switch await passkey.getCredential(assertionOptions: assertionOptions) {
        case .success(let res):
            return WebBridgePluginResult.success(
                JSONValue([
                    "credentialId": res.id,
                    "clientDataJSON": res.response.clientDataJSON,
                    "authenticatorData": res.response.authenticatorData,
                    "signature": res.response.signature,
                    "userHandle": res.response.userHandle,
                    "authenticatorAttachment": res.authenticatorAttachment?.rawValue,
                ])
            )
        case .canceled(let reason):
            return errorResult("WebBridgePasskeyPlugin.handleGet: Canceled: \(reason)", type: "ABORTED")
        case .failure(let error):
            let type: String = {
                switch error {
                case .passkeysNoCredential: return "TYPE_NO_CREDENTIAL"
                case .general(_, _, let identifier): return identifier?.value ?? "unknown"
                }
            }()
            return errorResult("WebBridgePasskeyPlugin.handleGet: \(error.description)", type: type)
        }
    }

    private func handleCreate(_ message: WebBridgePluginMessage) async -> WebBridgePluginResult {
        struct Discriminator: Decodable { let context: String? }
        let raw = message.payload.params ?? "{}"
        do {
            let disc = try coder.decodeFromString(raw, as: Discriminator.self)
            if disc.context != nil {
                // Flow create
                let params = try coder.decodeFromString(raw, as: FlowCreateParams.self)

                let context = params.context.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !context.isEmpty else {
                    return errorResult("WebBridgePasskeyPlugin.handleFlowCreate:'context' cannot be empty")
                }
                guard let challenge = context.data(using: .utf8)?.encodeToBase64UrlSafe() else {
                    return errorResult("WebBridgePasskeyPlugin.handleFlowCreate: Invalid UTF-8 in 'context'")
                }
                let rpId = params.relyingPartyId.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !rpId.isEmpty else {
                    return errorResult("WebBridgePasskeyPlugin.handleFlowCreate: 'relyingPartyId' cannot be empty")
                }
                let rpName = params.relyingPartyName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !rpName.isEmpty else {
                    return errorResult("WebBridgePasskeyPlugin.handleFlowCreate: 'relyingPartyName' cannot be empty")
                }
                let userName = params.userName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !userName.isEmpty else {
                    return errorResult("WebBridgePasskeyPlugin.handleFlowCreate: 'userName' cannot be empty")
                }
                let userDisplayName = params.userDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !userDisplayName.isEmpty else {
                    return errorResult("WebBridgePasskeyPlugin.handleFlowCreate: 'userDisplayName' cannot be empty")
                }

                let exclude = credentialIds(credsIds: params.credsIds, credId: params.credId)

                let attestationOptions = AttestationOptions(
                    rp: .init(id: rpId, name: rpName),
                    user: .init(id: Data.secureRandom(count: 32).encodeToBase64UrlSafe(), name: userName, displayName: userDisplayName),
                    challenge: ChallengeID(challenge),
                    pubKeyCredParams: [
                        .init(type: .publicKey, alg: .ES256),
                        .init(type: .publicKey, alg: .RS256),
                    ],
                    attestation: AttestationConveyancePreference.none,
                    authenticatorSelection: .init(authenticatorAttachment: .platform, userVerification: .required, residentKey: .preferred),
                    timeout: defaultTimeoutMs,
                    excludeCredentials: exclude.isEmpty ? nil : exclude.map { PublicKeyCredentialDescriptor(id: $0, type: .publicKey) }
                )

                switch await passkey.createCredential(attestationOptions: attestationOptions) {
                case .success(let res):
                    return WebBridgePluginResult.success(
                        JSONValue([
                            "credentialId": res.id,
                            "clientDataJSON": res.response.clientDataJSON,
                            "attestationObject": res.response.attestationObject,
                            "authenticatorAttachment": res.authenticatorAttachment?.rawValue,
                        ])
                    )
                case .canceled(let reason):
                    return errorResult("WebBridgePasskeyPlugin.handleFlowCreate: Canceled: \(reason)", type: "ABORTED")
                case .failure(let error):
                    let type: String = {
                        switch error {
                        case .passkeysNoCredential: return "TYPE_NO_CREDENTIAL"
                        case .general(_, _, let identifier): return identifier?.value ?? "unknown"
                        }
                    }()
                    return errorResult("WebBridgePasskeyPlugin.handleFlowCreate: \(error.description)", type: type)
                }
            } else {
                // Enrollment create (full WebAuthn shape)
                let params = try coder.decodeFromString(raw, as: EnrollmentParams.self)

                let challenge = params.challenge
                guard !challenge.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return errorResult("WebBridgePasskeyPlugin.handleEnrollmentCreate: 'challenge' is required")
                }

                let mappedAlgs: [AttestationOptions.PubKeyCredParams] = params.pubKeyCredParams.compactMap { p in
                    KeyAlgorithmType(rawValue: p.alg).map { .init(type: .publicKey, alg: $0) }
                }
                guard !mappedAlgs.isEmpty else {
                    return errorResult("WebBridgePasskeyPlugin.handleEnrollmentCreate: Unsupported algorithm in pubKeyCredParams")
                }

                let attestation = params.attestation.flatMap { AttestationConveyancePreference(rawValue: $0) } ?? .none
                let authSel = params.authenticatorSelection
                let authenticatorSelection = AttestationOptions.AuthenticatorSelection(
                    authenticatorAttachment: authSel?.authenticatorAttachment
                        .flatMap { AuthenticatorAttachment(rawValue: $0) } ?? .platform,
                    userVerification: authSel?.userVerification.flatMap { UserVerification(rawValue: $0) } ?? .required,
                    residentKey: authSel?.residentKey.flatMap { ResidentKey(rawValue: $0) } ?? .preferred
                )

                let timeout = params.timeout.map { Timeout(milliseconds: Int64($0)) } ?? defaultTimeoutMs
                var excludeCredentials: [PublicKeyCredentialDescriptor]?
                if let descriptors = params.excludeCredentials {
                    var mapped: [PublicKeyCredentialDescriptor] = []
                    mapped.reserveCapacity(descriptors.count)
                    for cred in descriptors {
                        guard let rawType = cred.type?.trimmingCharacters(in: .whitespacesAndNewlines), !rawType.isEmpty else {
                            return errorResult("WebBridgePasskeyPlugin.handleEnrollmentCreate: 'excludeCredentials.type' is required")
                        }
                        guard let type = CredentialType(rawValue: rawType) else {
                            return errorResult("WebBridgePasskeyPlugin.handleEnrollmentCreate: Unsupported credential type '\(rawType)'")
                        }
                        mapped.append(
                            PublicKeyCredentialDescriptor(
                                id: cred.id,
                                type: type,
                                transports: cred.transports?.compactMap { TransportType(rawValue: $0) }
                            )
                        )
                    }
                    excludeCredentials = mapped
                }

                let userId = params.user.id ?? Data.secureRandom(count: 32).encodeToBase64UrlSafe()

                let attestationOptions = AttestationOptions(
                    rp: .init(id: params.rp.id, name: params.rp.name),
                    user: .init(id: userId, name: params.user.name, displayName: params.user.displayName),
                    challenge: ChallengeID(challenge),
                    pubKeyCredParams: mappedAlgs,
                    attestation: attestation,
                    authenticatorSelection: authenticatorSelection,
                    timeout: timeout,
                    excludeCredentials: excludeCredentials
                )

                switch await passkey.createCredential(attestationOptions: attestationOptions) {
                case .success(let res):
                    return WebBridgePluginResult.success(
                        JSONValue([
                            "id": JSONValue(res.id),
                            "rawId": JSONValue(res.id),
                            "type": JSONValue("public-key"),
                            "response": JSONValue([
                                "clientDataJSON": res.response.clientDataJSON,
                                "attestationObject": res.response.attestationObject,
                            ]),
                            "authenticatorAttachment": JSONValue(res.authenticatorAttachment?.rawValue),
                        ])
                    )
                case .canceled(let reason):
                    return errorResult(
                        "WebBridgePasskeyPlugin.handleEnrollmentCreate: Canceled: \(reason)",
                        type: "ABORTED"
                    )
                case .failure(let error):
                    let type: String = {
                        switch error {
                        case .passkeysNoCredential: return "TYPE_NO_CREDENTIAL"
                        case .general(_, _, let identifier): return identifier?.value ?? "unknown"
                        }
                    }()
                    return errorResult("WebBridgePasskeyPlugin.handleEnrollmentCreate: \(error.description)", type: type)
                }
            }
        } catch {
            return errorResult("WebBridgePasskeyPlugin.handleCreate: Invalid JSON: \(error.localizedDescription)")
        }
    }

    private func errorResult(_ message: String, type: String? = nil) -> WebBridgePluginResult {
        let normalizedType = type?.uppercased()
        let effectiveType = (normalizedType == "UNKNOWN") ? nil : normalizedType
        return WebBridgePluginResult.error(message: message, type: effectiveType)
    }

    private func credentialIds(credsIds: [String]?, credId: String?) -> [String] {
        if let arr = credsIds?.filter({ !$0.isEmpty }), !arr.isEmpty { return arr }
        if let one = credId, !one.isEmpty { return [one] }
        return []
    }
}

@available(iOS 16.0, *)
extension WebBridgePasskeyPlugin {
    internal static func create(resolver: any DIContainerResolver) throws -> WebBridgePasskeyPlugin {
        WebBridgePasskeyPlugin(
            passkey: try resolver.getOrThrow(type: (any PasskeyProtocol).self),
            localInfo: try resolver.getOrThrow(type: (any LocalInfo).self),
            coder: try resolver.getOrThrow(type: (any JSONCoder).self)
        )
    }
}

private struct FlowCreateParams: Decodable {
    let context: String
    let relyingPartyId: String
    let relyingPartyName: String
    let userName: String
    let userDisplayName: String
    let credsIds: [String]?
    let credId: String?
}

private struct EnrollmentParams: Decodable {
    struct RP: Decodable {
        let id: String
        let name: String
    }
    struct User: Decodable {
        let id: String?
        let name: String
        let displayName: String
    }
    struct PubKeyParam: Decodable {
        let type: String?
        let alg: Int
    }
    struct AuthenticatorSelection: Decodable {
        let authenticatorAttachment: String?
        let userVerification: String?
        let residentKey: String?
    }
    struct Descriptor: Decodable {
        let id: String
        let type: String?
        let transports: [String]?
    }

    let challenge: String
    let rp: RP
    let user: User
    let pubKeyCredParams: [PubKeyParam]
    let attestation: String?
    let authenticatorSelection: AuthenticatorSelection?
    let timeout: Int?
    let excludeCredentials: [Descriptor]?
}
