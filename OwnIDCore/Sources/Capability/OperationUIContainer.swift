import Foundation

/// Presents SDK operation UI by hosting an ``OperationController`` in the app's view hierarchy.
///
/// Implementations are presentation bridges for SDK-owned operation UI. They locate or create a platform container,
/// show UI for the supplied controller, and leave operation state, cancellation, and terminal results owned by the
/// controller. App-hosted SwiftUI rendering uses `OwnIDOperationView` and its own container lifecycle instead of this
/// SDK-managed presentation hook.
public protocol OperationUIContainer: Capability, Sendable {
    /// Presents the operation UI managed by `controller`.
    ///
    /// This method runs on the main actor and is expected to schedule or start presentation for the active operation.
    /// Implementations may present a SwiftUI sheet, a UIKit controller, or another host surface. Immediate
    /// presentation failures, including a missing presenter or an already active container, should be reported by
    /// aborting the supplied controller with an appropriate presentation reason.
    ///
    /// A container should not complete the operation by itself or turn dismissal into success or failure. Once
    /// presented, operation content and container lifecycle decide whether user dismissal cancels the operation.
    ///
    /// - Parameters:
    ///   - controller: The operation controller whose UI should be displayed.
    @MainActor func show<Controller: OperationController>(controller: Controller)
}
