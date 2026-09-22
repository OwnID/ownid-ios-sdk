import Foundation

/// Presents SDK operation UI by hosting an ``OperationController`` in the app's view hierarchy.
///
/// Implementations are presentation bridges for SDK-owned operation UI. They present the supplied controller in an
/// app-visible surface while leaving operation state, cancellation, and terminal results owned by the controller.
/// App-hosted SwiftUI rendering uses `OwnIDOperationView` and its own presentation lifecycle instead of this
/// SDK-managed presentation hook.
public protocol OperationUIContainer: Capability, Sendable {
    /// Presents the operation UI managed by `controller`.
    ///
    /// This method runs on the main actor and starts presentation for the active operation. Implementations may use a
    /// SwiftUI sheet, UIKit controller, or another host surface. Throw when presentation cannot start immediately,
    /// such as when there is no presenter or another container is already active. A synchronous throw should leave the
    /// supplied controller unsettled; a container may still abort it later if a presentation that started cannot finish.
    ///
    /// A container should not complete the operation by itself or turn dismissal into success or failure. Once
    /// presented, operation content and container lifecycle decide whether user dismissal cancels the operation.
    ///
    /// - Parameter controller: The operation controller whose UI should be displayed.
    /// - Throws: An implementation-defined error when presentation cannot be started immediately.
    @MainActor func show<Controller: OperationController>(controller: Controller) throws
}
