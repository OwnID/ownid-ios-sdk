import Foundation
import UIKit

internal final class PasskeyAttestationUIImpl: PasskeyAttestationUI {
    private let uiContextProvider: @Sendable () throws -> any UIContextProvider
    private let passkey: any PasskeyProtocol
    private let logger: OwnIDLogRouter?

    init(
        uiContextProvider: @escaping @Sendable () throws -> any UIContextProvider,
        passkey: any PasskeyProtocol,
        logger: OwnIDLogRouter?
    ) {
        self.uiContextProvider = uiContextProvider
        self.passkey = passkey
        self.logger = logger
    }

    func isAvailable(params: (any CapabilityParams)?) async -> Bool {
        await passkey.isAvailable(params: params)
    }

    @MainActor
    func createCredential(options: AttestationOptions) async -> PasskeyResult<AttestationResult> {
        let window: UIWindow
        do {
            window = try uiContextProvider().current().requireWindow()
        } catch {
            logger?.logW(source: self, prefix: #function, message: "UI context resolution failed", cause: error)
            return .failure(
                .general("Failed to resolve a presentation window: \(error.localizedDescription)", error.asSendableError())
            )
        }
        return await passkey.createCredential(window: window, attestationOptions: options)
    }
}
