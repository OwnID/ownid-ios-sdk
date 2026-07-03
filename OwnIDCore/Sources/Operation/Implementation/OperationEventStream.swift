import Foundation

/// Operation-owned async event ingress.
///
/// Operation runtimes use this stream to accept lifecycle, UI, API, timeout, and abort events for one operation run.
/// Accepted yields are serialized by the actor until ``finish()``. Finishing the stream is terminal; later yields return
/// `false` so the owner can avoid assuming a late event was accepted after settlement or cleanup.
internal actor OperationEventStream<Event: Sendable> {
    private var continuation: AsyncStream<Event>.Continuation?
    internal let sequence: AsyncStream<Event>

    internal init() {
        var cont: AsyncStream<Event>.Continuation!
        self.sequence = AsyncStream<Event> { c in cont = c }
        self.continuation = cont
    }

    deinit {
        continuation?.finish()
    }

    @discardableResult
    internal func yield(_ event: Event) -> Bool {
        guard let continuation else { return false }
        continuation.yield(event)
        return true
    }

    internal func finish() {
        continuation?.finish()
        continuation = nil
    }
}
