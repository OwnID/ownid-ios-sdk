@_spi(OwnIDInternal) import OwnIDCore
import SwiftUI

/// Renders one app-hosted OwnID operation in your SwiftUI hierarchy.
///
/// Supports login ID collection, email verification, and phone verification operations.
///
/// Apply `useAppHostedComponent` to a supported operation, call `start`, keep the returned
/// ``OwnIDOperationUIController`` in UI state, and pass it to this view. The view uses matching content overrides from
/// the surrounding SwiftUI environment when provided; otherwise it uses content registered for the OwnID instance that
/// created the controller. The app observes the terminal ``OperationResult`` through
/// ``OwnIDOperationUIController/whenSettled()``; this view does not invoke app success, failure, or cancellation
/// callbacks directly.
///
/// Lifecycle is controlled in one of two modes:
///
/// - Embedded mode: omit ``OwnIDUIContainerController`` when the view itself owns the lifecycle. Removing the view
///   before the operation settles cancels the operation with a user-close reason.
/// - App-container mode: pass an ``OwnIDUIContainerController`` when your app presents the view in its own sheet,
///   dialog, full-screen cover, or overlay. Use the same controller for the whole presentation cycle. The app starts
///   and reports container dismissal, while this view keeps the operation and container lifecycle aligned. Removing
///   this view before ``OwnIDUIContainerController/markClosed()`` does not cancel the operation; the operation waits
///   for the container close signal or for operation settlement.
///
/// After the operation settles, this view renders no operation content. If the SDK instance is no longer available,
/// required strings or content are missing, or the operation type is unsupported, the operation is canceled with a
/// system error reason.
///
/// Content override builders and providers own rendering and user-event wiring only. Invoke callbacks from the
/// supplied UI state for user actions. Custom content owns visible busy indicators, error display, and one-time focus
/// behavior, while validation, resend/cancel/"not you" handling, abort, timeout, and final settlement remain owned by
/// the SDK operation controller.
public struct OwnIDOperationView<Success: Sendable, Failure: OperationFailure>: View {
    @Environment(\.colorScheme) private var colorScheme

    private let operationUIController: OwnIDOperationUIController<Success, Failure>
    private let containerController: OwnIDUIContainerController?
    private let theme: OwnIDTheme?
    private let errorTextProvider: ((ErrorCode) -> String)?

    /// Creates a view for an app-hosted OwnID operation.
    ///
    /// - Parameters:
    ///   - operationUIController: Controller returned after starting an app-hosted operation with
    ///     `useAppHostedComponent`.
    ///   - containerController: Optional bridge for a sheet, dialog, full-screen cover, or overlay owned by the app.
    ///     Create a new controller for each presentation cycle, provide a close action that starts dismissal, pass that
    ///     same controller to the presented container, and attach ``View/ownIDOperationContainer(_:)`` to the presented
    ///     container root. Do not replace the controller while the current container is still open, and do not use view
    ///     removal as a substitute for ``OwnIDUIContainerController/markClosed()``.
    ///   - theme: Optional theme for this operation UI. When `nil`, the view captures the current SwiftUI color
    ///     scheme and accent color.
    ///   - errorTextProvider: Optional provider from SDK-reported ``ErrorCode`` values to text shown by built-in
    ///     operation content and custom content that chooses to use the provider. When omitted, built-in content shows
    ///     the operation ``UIError/localizedMessage``.
    public init(
        operationUIController: OwnIDOperationUIController<Success, Failure>,
        containerController: OwnIDUIContainerController? = nil,
        theme: OwnIDTheme? = nil,
        errorTextProvider: ((ErrorCode) -> String)? = nil
    ) {
        self.operationUIController = operationUIController
        self.containerController = containerController
        self.theme = theme
        self.errorTextProvider = errorTextProvider
    }

    public var body: some View {
        let resolvedTheme = theme ?? OwnIDTheme.capture(colorScheme: colorScheme)

        ZStack {
            Color.clear
                .frame(width: 0, height: 0)

            OperationLifecycleHost(
                instanceName: operationUIController.instanceName,
                operationController: operationUIController,
                renderController: operationUIController.operationController,
                containerController: containerController,
                errorTextProvider: errorTextProvider
            )
            .id(operationUIController.operationID)
        }
        .environment(\.ownIDTheme, resolvedTheme)
        .tintCompat(resolvedTheme.colors.primary)
    }
}
