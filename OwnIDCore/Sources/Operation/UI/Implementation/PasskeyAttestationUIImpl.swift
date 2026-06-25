import Foundation

/// Default Core adapter from operation UI to the registered platform passkey capability.
///
/// The adapter preserves the ``PasskeyResult`` boundary: setup or provider failures are returned as
/// ``PasskeyResult/failure(_:)`` for the operation to classify.
internal final class PasskeyAttestationUIImpl: PasskeyAttestationUI {
    private let passkeyProvider: @Sendable () throws -> any PasskeyProtocol

    init(passkeyProvider: @escaping @Sendable () throws -> any PasskeyProtocol) {
        self.passkeyProvider = passkeyProvider
    }

    @MainActor
    func createCredential(options: AttestationOptions) async -> PasskeyResult<AttestationResult> {
        do {
            let passkey = try passkeyProvider()
            return await passkey.createCredential(attestationOptions: options)
        } catch let missing as MissingDependencyError {
            return .failure(.general("Missing dependency: \(missing.dependencyName)", missing))
        } catch {
            return .failure(.general(error.localizedDescription, error))
        }
    }
}
