@_spi(OwnIDInternal) import OwnIDCore

internal final class PhoneVerificationUIImpl: PhoneVerificationUI {
    private let showContainer: @MainActor @Sendable (any PhoneVerificationOperationController) throws -> Void

    internal init(showContainer: @MainActor @Sendable @escaping (any PhoneVerificationOperationController) throws -> Void) {
        self.showContainer = showContainer
    }

    @MainActor
    internal func start(controller: any PhoneVerificationOperationController) -> PhoneVerificationOperationFailure.Integration? {
        do {
            try showContainer(controller)
            return nil
        } catch let missing as MissingDependencyError {
            return .ui(
                errorCode: .integrationError,
                message: "Missing dependency: \(missing.dependencyName)",
                underlyingError: missing
            )
        } catch {
            return .ui(
                errorCode: .integrationError,
                message: "Failed to show container: \(error.localizedDescription)",
                underlyingError: error
            )
        }
    }
}
