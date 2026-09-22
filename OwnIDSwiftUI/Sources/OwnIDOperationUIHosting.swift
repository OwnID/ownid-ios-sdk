@_spi(OwnIDInternal) import OwnIDCore

extension OperationEntry
where Params == EmailVerificationOperationParams?, Success == AccessOrProofToken, Failure == EmailVerificationOperationFailure {
    /// Returns an email-verification operation entry whose UI is rendered by the app with ``OwnIDOperationView``.
    ///
    /// Use this when you want to present OwnID verification inside your SwiftUI hierarchy, sheet, dialog, full-screen
    /// cover, or overlay instead of letting the SDK present its built-in container.
    public var appHostedComponent: OwnIDOperationUIEntry<Params, Success, Failure> {
        withOperationUIHostingScope("OperationUIHosting.\(OperationType.emailVerification.rawValue)")
    }
}

extension OperationEntry
where Params == PhoneVerificationOperationParams?, Success == AccessOrProofToken, Failure == PhoneVerificationOperationFailure {
    /// Returns a phone-verification operation entry whose UI is rendered by the app with ``OwnIDOperationView``.
    ///
    /// Use this when you want to present OwnID verification inside your SwiftUI hierarchy, sheet, dialog, full-screen
    /// cover, or overlay instead of letting the SDK present its built-in container.
    public var appHostedComponent: OwnIDOperationUIEntry<Params, Success, Failure> {
        withOperationUIHostingScope("OperationUIHosting.\(OperationType.phoneNumberVerification.rawValue)")
    }
}

extension OperationEntry where Params == LoginIDCollectOperationParams?, Success == LoginID, Failure == LoginIDCollectOperationFailure {
    /// Returns a login-ID-collection operation entry whose UI is rendered by the app with ``OwnIDOperationView``.
    ///
    /// Use this when you want to present the collection form inside your SwiftUI hierarchy, sheet, dialog,
    /// full-screen cover, or overlay instead of letting the SDK present its built-in container.
    public var appHostedComponent: OwnIDOperationUIEntry<Params, Success, Failure> {
        withOperationUIHostingScope("OperationUIHosting.\(OperationType.loginIDCollect.rawValue)")
    }
}

/// OwnID operation prepared for app-hosted SwiftUI rendering.
///
/// Use this wrapper when your app owns the presentation for an operation. Check ``availability(params:)`` or
/// ``isAvailable(params:)`` with the same parameters you plan to pass to ``start(params:)``. For optional-parameter
/// operations, the no-argument overloads pass `nil`, which lets the operation resolve defaults from the current OwnID
/// context.
///
/// This wrapper supports operation entries obtained from an OwnID SDK instance, not arbitrary custom
/// ``OperationEntry`` implementations.
///
/// With an app-hosted entry, the SDK starts the operation but leaves presentation to your app. The entry remains tied
/// to the SDK instance and context from which it was derived. ``start(params:)`` returns an
/// ``OwnIDOperationUIController`` that should be kept in UI state, rendered by ``OwnIDOperationView``, and observed
/// for its terminal ``OperationResult``. Availability is a preflight signal only; start may still settle with
/// cancellation or a typed failure if runtime state changes.
public struct OwnIDOperationUIEntry<Params, Success: Sendable, Failure: OperationFailure>: Sendable {
    private let instanceName: InstanceName
    private let instanceResolver: any DIContainerResolver
    private let delegate: any OperationEntry<Params, Success, Failure>

    /// The operation type started by this entry.
    public var operationType: OperationType { delegate.operationType }

    internal init(
        instanceName: InstanceName,
        instanceResolver: any DIContainerResolver,
        delegate: any OperationEntry<Params, Success, Failure>
    ) {
        self.instanceName = instanceName
        self.instanceResolver = instanceResolver
        self.delegate = delegate
    }

    /// Returns the current availability for starting this operation with `params`.
    ///
    /// Use the same value you plan to pass to ``start(params:)``.
    public func availability(params: Params) async -> Availability {
        await delegate.availability(params: params)
    }

    /// Returns `true` when this operation can currently start with `params`.
    ///
    /// Use ``availability(params:)`` when the unavailable reason matters.
    public func isAvailable(params: Params) async -> Bool {
        if case .available = await availability(params: params) { return true }
        return false
    }

    /// Starts the operation for rendering in ``OwnIDOperationView``.
    ///
    /// Keep the returned controller while the operation is relevant to your screen. Render it with
    /// ``OwnIDOperationView`` and observe its terminal result through
    /// ``OwnIDOperationUIController/whenSettled()``. Starting more than one operation is app-owned; keep each
    /// operation controller tied to the UI and presentation container that owns that operation.
    ///
    /// This method starts the operation but does not show SDK-owned UI. If runtime state changes after start, the
    /// returned controller settles with ``OperationResult/failure(_:)`` or ``OperationResult/canceled(_:)``.
    ///
    /// - Warning: This method traps if the operation runtime cannot be resolved from the entry's bound scope.
    public func start(params: Params) -> OwnIDOperationUIController<Success, Failure> {
        OwnIDOperationUIController(
            instanceName: instanceName,
            instanceResolver: instanceResolver,
            delegate: delegate.start(params: params)
        )
    }
}

extension OwnIDOperationUIEntry {
    /// Returns availability for operations whose parameter object is optional.
    ///
    /// This overload passes `nil` parameters, allowing the operation to use values from the current OwnID context.
    public func availability<Wrapped>() async -> Availability where Params == Wrapped? {
        await availability(params: nil)
    }

    /// Returns `true` when an optional-parameter operation can currently start.
    ///
    /// This overload passes `nil` parameters. Use ``availability()`` when the unavailable reason matters.
    public func isAvailable<Wrapped>() async -> Bool where Params == Wrapped? {
        await isAvailable(params: nil)
    }

    /// Starts an optional-parameter operation without passing parameters.
    ///
    /// This overload passes `nil` parameters, allowing the operation to use values from the current OwnID context.
    ///
    /// - Warning: This method traps if the operation runtime cannot be resolved from the entry's bound scope.
    public func start<Wrapped>() -> OwnIDOperationUIController<Success, Failure> where Params == Wrapped? {
        start(params: nil)
    }
}

/// Controls one app-hosted OwnID operation rendered by ``OwnIDOperationView``.
///
/// The controller is tied to the OwnID SDK instance that created it. Keep it while the operation is relevant to your
/// UI, render it with ``OwnIDOperationView``, and call ``whenSettled()`` from your own task when you need the terminal
/// ``OperationResult``.
///
/// ``OwnIDOperationView`` handles cancellation while your app keeps the controller tied to either an embedded view or a
/// reported app-owned container lifecycle. If your UI stops owning an unsettled controller without rendering
/// ``OwnIDOperationView`` or without reporting the container close, call ``abort(reason:)`` with a meaningful
/// ``Reason`` for owner-driven cleanup. The controller does not retain app UI state.
///
/// A controller represents one started operation. It does not restart an operation after settlement; call `start` again
/// on the same bound entry when you need a new operation run and controller.
public final class OwnIDOperationUIController<Success: Sendable, Failure: OperationFailure>: OperationController {
    internal let instanceName: InstanceName
    internal let instanceResolver: any DIContainerResolver
    private let delegate: any OperationController<Success, Failure>

    internal init(
        instanceName: InstanceName,
        instanceResolver: any DIContainerResolver,
        delegate: any OperationController<Success, Failure>
    ) {
        self.instanceName = instanceName
        self.instanceResolver = instanceResolver
        self.delegate = delegate
    }

    /// The unique identifier for this operation instance.
    public var operationID: OperationID { delegate.operationID }

    internal var operationController: any OperationController<Success, Failure> { delegate }

    /// Waits for the operation to finish and returns its terminal result.
    ///
    /// Multiple tasks may await the same controller. Canceling a task that is only waiting here does not cancel the
    /// operation; use ``abort(reason:)`` when the owner needs to stop an unsettled operation.
    public func whenSettled() async -> OperationResult<Success, Failure> {
        await delegate.whenSettled()
    }

    /// Requests cancellation with an explicit reason.
    ///
    /// Calling this after the operation has already settled has no effect.
    public func abort(reason: Reason) {
        delegate.abort(reason: reason)
    }
}

extension OperationEntry {
    fileprivate func withOperationUIHostingScope(_ scopeName: String) -> OwnIDOperationUIEntry<Params, Success, Failure> {
        guard let scoped = self as? any ScopedOperationEntry else {
            preconditionFailure("appHostedComponent is only supported for OwnID operations from an OwnID SDK instance")
        }

        let instanceName = scoped.instanceName
        let scopedEntry = scoped.withOperationScope(scopeName) { container in
            container.register(
                (any OperationUIContainer).self,
                instance: NoOpOperationUIContainer(logger: container.getOrNil(type: OwnIDLogRouter.self)) as any OperationUIContainer
            )
        }

        guard let entry = scopedEntry as? AnyScopedOperationEntry<Params, Success, Failure> else {
            preconditionFailure("OwnID could not prepare this operation for app-hosted UI")
        }
        return OwnIDOperationUIEntry(
            instanceName: instanceName,
            instanceResolver: entry.operationResolver,
            delegate: entry
        )
    }
}

private struct NoOpOperationUIContainer: OperationUIContainer {
    fileprivate let logger: OwnIDLogRouter?

    @MainActor func show<Controller: OperationController>(controller: Controller) {
        logger?.logI(source: self, prefix: "show", message: "Skipping SDK UI container for operation UI hosting: \(controller.operationID)")
    }
}
