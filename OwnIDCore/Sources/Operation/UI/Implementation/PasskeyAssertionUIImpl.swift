import Foundation
import UIKit

internal final class PasskeyAssertionUIImpl: PasskeyAssertionUI {
    private let uiContextProvider: @Sendable () throws -> any UIContextProvider
    private let passkeyProvider: @Sendable () throws -> any PasskeyProtocol
    private let logger: OwnIDLogRouter?

    init(
        uiContextProvider: @escaping @Sendable () throws -> any UIContextProvider,
        passkeyProvider: @escaping @Sendable () throws -> any PasskeyProtocol,
        logger: OwnIDLogRouter?
    ) {
        self.uiContextProvider = uiContextProvider
        self.passkeyProvider = passkeyProvider
        self.logger = logger
    }

    @MainActor
    func getCredential(options: AssertionOptions) async -> PasskeyResult<AssertionResult> {
        do {
            let passkey = try passkeyProvider()
            let window: UIWindow
            do {
                window = try uiContextProvider().current().requireWindow()
            } catch {
                logger?.logW(source: self, prefix: #function, message: "UI context resolution failed", cause: error)
                return .failure(
                    .general("Failed to resolve a presentation window: \(error.localizedDescription)", error.asSendableError())
                )
            }
            return await passkey.getCredential(window: window, assertionOptions: options)
        } catch let missing as MissingDependencyError {
            return .failure(.general("Missing dependency: \(missing.dependencyName)", missing))
        } catch {
            return .failure(.general(error.localizedDescription, error))
        }
    }
}
