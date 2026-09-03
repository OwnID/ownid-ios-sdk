import SwiftUI
import Testing
import UIKit

enum SwiftUITestTimeoutError: Error, Sendable {
    case timedOut(String)
}

struct ButtonSlotSnapshot: Equatable {
    let isBusy: Bool
    let isEnabled: Bool
    let accessibilityLabel: String

    static func ready(accessibilityLabel: String) -> Self {
        Self(isBusy: false, isEnabled: true, accessibilityLabel: accessibilityLabel)
    }

    static func busy(accessibilityLabel: String) -> Self {
        Self(isBusy: true, isEnabled: false, accessibilityLabel: accessibilityLabel)
    }
}

struct SwiftUIRuntimeFittingSizeExpectation {
    let width: CGFloat
    let maxHeight: CGFloat
    let maxReportedWidth: CGFloat
    let maxReportedHeight: CGFloat

    static let constrainedOperationUI = Self(
        width: 220,
        maxHeight: 520,
        maxReportedWidth: 480,
        maxReportedHeight: 1_200
    )

}

@MainActor
protocol SwiftUIRuntimeSettlingHost {
    func settle(cycles: Int) async
}

func withSwiftUITestTimeout<T: Sendable>(
    _ description: String,
    seconds: UInt64 = 5,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        defer { group.cancelAll() }
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            throw SwiftUITestTimeoutError.timedOut(description)
        }
        let value = try await group.next()!
        return value
    }
}

@MainActor
final class SwiftUIRuntimeHost<Content: View>: SwiftUIRuntimeSettlingHost {
    let host: UIHostingController<Content>
    private let window: UIKitRuntimeTestWindow
    private let rootViewController = UIViewController()

    init(rootView: Content, size: CGSize = CGSize(width: 320, height: 420)) {
        host = UIHostingController(rootView: rootView)
        window = UIKitRuntimeTestWindow(size: size)

        rootViewController.addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        rootViewController.view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: rootViewController.view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: rootViewController.view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: rootViewController.view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: rootViewController.view.bottomAnchor),
        ])
        host.didMove(toParent: rootViewController)
        window.show(root: rootViewController)

        layout()
    }

    func update(rootView: Content) {
        host.rootView = rootView
        layout()
    }

    func layout() {
        rootViewController.view.setNeedsLayout()
        rootViewController.view.layoutIfNeeded()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
    }

    func settle(cycles: Int = 3) async {
        for _ in 0..<cycles {
            await Task.yield()
            layout()
        }
    }

    func fittingSize(width: CGFloat, maxHeight: CGFloat = CGFloat.greatestFiniteMagnitude) -> CGSize {
        layout()
        return host.sizeThatFits(in: CGSize(width: width, height: maxHeight))
    }

    @discardableResult
    func assertFittingSize(_ expectation: SwiftUIRuntimeFittingSizeExpectation) -> CGSize {
        let fittingSize = fittingSize(width: expectation.width, maxHeight: expectation.maxHeight)

        #expect(fittingSize.width > 0)
        #expect(fittingSize.width <= expectation.maxReportedWidth)
        #expect(fittingSize.height > 0)
        #expect(fittingSize.height <= expectation.maxReportedHeight)

        return fittingSize
    }

    func assertLaidOut(_ view: UIView, maxWidth: CGFloat) {
        #expect(view.frame.width > 0)
        #expect(view.frame.width <= maxWidth)
        #expect(view.frame.height > 0)
    }

    func textFields() -> [UITextField] {
        host.view.ownIDTestDescendants().compactMap { $0 as? UITextField }
    }

    func close() {
        host.willMove(toParent: nil)
        host.view.removeFromSuperview()
        host.removeFromParent()
        window.close()
    }
}

@MainActor
// Main-actor isolation owns all mutable state; unchecked sendability only allows capture by async test tasks.
final class RuntimeSnapshotRecorder<Snapshot: Sendable>: @unchecked Sendable {
    private var values: [Snapshot] = []
    private var waiters: [SnapshotWaiter] = []

    func record(_ snapshot: Snapshot) {
        let snapshotIndex = values.count
        values.append(snapshot)
        let matchingWaiters = waiters.filter {
            snapshotIndex >= $0.minimumIndex && $0.predicate(snapshot)
        }
        let matchingWaiterIDs = Set(matchingWaiters.map(\.id))
        waiters.removeAll { matchingWaiterIDs.contains($0.id) }
        for waiter in matchingWaiters {
            waiter.continuation.resume(returning: snapshot)
        }
    }

    func snapshots() -> [Snapshot] {
        values
    }

    func waitForSnapshot<Host: SwiftUIRuntimeSettlingHost>(
        matching predicate: @escaping (Snapshot) -> Bool,
        afterSnapshotCount: Int = 0,
        host: Host,
        description: String = "runtime snapshot"
    ) async throws -> Snapshot {
        if let snapshot = values.dropFirst(min(afterSnapshotCount, values.count)).last(where: predicate) {
            return snapshot
        }

        let waitTask = Task { @MainActor in
            try await self.waitForRecordedSnapshot(
                matching: predicate,
                afterSnapshotCount: afterSnapshotCount
            )
        }
        defer { waitTask.cancel() }

        await host.settle(cycles: 20)
        return try await withSwiftUITestTimeout(description, seconds: 2) {
            do {
                return try await waitTask.value
            } catch is CancellationError {
                let values = await MainActor.run { self.values }
                throw RuntimeSnapshotTimeoutError(context: description, snapshots: values)
            }
        }
    }

    private func waitForRecordedSnapshot(
        matching predicate: @escaping (Snapshot) -> Bool,
        afterSnapshotCount: Int
    ) async throws -> Snapshot {
        if let snapshot = values.dropFirst(min(afterSnapshotCount, values.count)).last(where: predicate) {
            return snapshot
        }

        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if let snapshot = values.dropFirst(min(afterSnapshotCount, values.count)).last(where: predicate) {
                    continuation.resume(returning: snapshot)
                } else {
                    waiters.append(
                        SnapshotWaiter(
                            id: waiterID,
                            minimumIndex: afterSnapshotCount,
                            predicate: predicate,
                            continuation: continuation
                        )
                    )
                }
            }
        } onCancel: {
            Task { @MainActor in self.cancelWaiter(id: waiterID) }
        }
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }

    private struct SnapshotWaiter {
        let id: UUID
        let minimumIndex: Int
        let predicate: (Snapshot) -> Bool
        let continuation: CheckedContinuation<Snapshot, any Error>
    }
}

private struct RuntimeSnapshotTimeoutError<Snapshot: Sendable>: Error, CustomStringConvertible {
    let context: String
    let snapshots: [Snapshot]

    var description: String {
        "Timed out waiting for \(context). Snapshots: \(snapshots)"
    }
}

struct RuntimeSnapshotProbe<Snapshot: Sendable>: UIViewRepresentable {
    typealias UIViewType = UIView

    let snapshot: Snapshot
    let recorder: RuntimeSnapshotRecorder<Snapshot>

    func makeUIView(context: UIViewRepresentableContext<RuntimeSnapshotProbe<Snapshot>>) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: UIViewRepresentableContext<RuntimeSnapshotProbe<Snapshot>>) {
        recorder.record(snapshot)
    }
}

@MainActor
func sendEditingChanged(to textField: UITextField) {
    for target in textField.allTargets {
        guard let targetObject = target.base as? NSObject else { continue }
        let actions = textField.actions(forTarget: targetObject, forControlEvent: .editingChanged) ?? []
        for action in actions {
            targetObject.perform(Selector(action), with: textField)
        }
    }
}

@MainActor
func enterText<Content: View>(
    _ value: String,
    in textField: UITextField,
    host: SwiftUIRuntimeHost<Content>
) async {
    textField.text = value
    sendEditingChanged(to: textField)
    await host.settle()
}

@MainActor
@discardableResult
func submitReturn(on textField: UITextField) throws -> Bool {
    let delegate = try #require(textField.delegate)
    return delegate.textFieldShouldReturn?(textField) ?? false
}

extension UIColor {
    func ownIDTestIsEqual(to other: UIColor, tolerance: CGFloat = 0.001) -> Bool {
        guard let lhs = ownIDTestRGBAComponents(), let rhs = other.ownIDTestRGBAComponents() else {
            return isEqual(other)
        }

        return abs(lhs.red - rhs.red) <= tolerance
            && abs(lhs.green - rhs.green) <= tolerance
            && abs(lhs.blue - rhs.blue) <= tolerance
            && abs(lhs.alpha - rhs.alpha) <= tolerance
    }

    private func ownIDTestRGBAComponents() -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }
        return (red, green, blue, alpha)
    }
}

extension UIView {
    fileprivate func ownIDTestDescendants() -> [UIView] {
        [self] + subviews.flatMap { $0.ownIDTestDescendants() }
    }
}
