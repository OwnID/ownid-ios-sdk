import Foundation
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

extension View {
    @ViewBuilder
    internal func overlayCompat<Content: View>(
        alignment: Alignment = .center,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if #available(iOS 15, *) {
            overlay(alignment: alignment, content: content)
        } else {
            ZStack(alignment: alignment) {
                self
                content()
            }
        }
    }

    @ViewBuilder
    internal func tintCompat(_ color: Color) -> some View {
        if #available(iOS 15, *) {
            tint(color)
        } else {
            accentColor(color)
        }
    }

    @ViewBuilder
    internal func onSubmitCompat(_ action: @escaping () -> Void) -> some View {
        if #available(iOS 15, *) {
            onSubmit(action)
        } else {
            self
        }
    }

    @ViewBuilder
    internal func animationCompat<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        if #available(iOS 15, *) {
            self.animation(animation, value: value)
        } else {
            self.animation(animation)
        }
    }

    @ViewBuilder
    internal func taskCompat(_ action: @escaping @MainActor @Sendable () async -> Void) -> some View {
        if #available(iOS 15, *) {
            task { await action() }
        } else {
            modifier(TaskCompatModifier(action: action))
        }
    }

    @ViewBuilder
    internal func taskCompat<ID: Hashable>(id: ID, _ action: @escaping @MainActor @Sendable () async -> Void) -> some View {
        if #available(iOS 15, *) {
            task(id: id) { await action() }
        } else {
            modifier(TaskCompatModifierWithID(id: id, action: action))
        }
    }

    @ViewBuilder
    internal func onChangeCompat<V: Equatable>(of value: V, perform action: @escaping @MainActor (V) -> Void) -> some View {
        if #available(iOS 14, *) {
            onChange(of: value, perform: action)
        } else {
            modifier(OnChangeCompatModifier(value: value, action: action))
        }
    }

    @ViewBuilder
    internal func ignoresSafeAreaCompat(_ edges: Edge.Set = .all) -> some View {
        if #available(iOS 15, *) {
            ignoresSafeArea(.all, edges: edges)
        } else {
            edgesIgnoringSafeArea(edges)
        }
    }

    @ViewBuilder
    internal func accessibilityLabelCompat(_ label: Text) -> some View {
        if #available(iOS 14, *) {
            accessibilityLabel(label)
        } else {
            accessibility(label: label)
        }
    }

    @ViewBuilder
    internal func accessibilityLabelCompat(_ label: String) -> some View {
        accessibilityLabelCompat(Text(label))
    }

    @ViewBuilder
    internal func accessibilityHiddenCompat(_ hidden: Bool) -> some View {
        if #available(iOS 14, *) {
            accessibilityHidden(hidden)
        } else {
            accessibility(hidden: hidden)
        }
    }

    @ViewBuilder
    internal func accessibilityHintCompat(_ hint: Text) -> some View {
        if #available(iOS 14, *) {
            accessibilityHint(hint)
        } else {
            accessibility(hint: hint)
        }
    }

    @ViewBuilder
    internal func accessibilityHintCompat(_ hint: String) -> some View {
        accessibilityHintCompat(Text(hint))
    }

    @ViewBuilder
    internal func accessibilityRespondsToUserInteractionCompat(_ responds: Bool) -> some View {
        if #available(iOS 15, *) {
            accessibilityRespondsToUserInteraction(responds)
        } else {
            self
        }
    }
}

private struct TaskCompatModifier: ViewModifier {
    private let action: @MainActor @Sendable () async -> Void
    @State private var task: Task<Void, Never>? = nil

    fileprivate init(action: @escaping @MainActor @Sendable () async -> Void) {
        self.action = action
    }

    fileprivate func body(content: Content) -> some View {
        content
            .onAppear {
                guard task == nil else { return }
                task = Task { await action() }
            }
            .onDisappear {
                task?.cancel()
                task = nil
            }
    }
}

private struct TaskCompatModifierWithID<ID: Hashable>: ViewModifier {
    private let id: ID
    private let action: @MainActor @Sendable () async -> Void
    @State private var task: Task<Void, Never>? = nil
    @State private var lastID: ID? = nil

    fileprivate init(id: ID, action: @escaping @MainActor @Sendable () async -> Void) {
        self.id = id
        self.action = action
    }

    fileprivate func body(content: Content) -> some View {
        content
            .onAppear { startIfNeeded(newID: id) }
            .onChangeCompat(of: id) { newID in startIfNeeded(newID: newID) }
            .onDisappear {
                task?.cancel()
                task = nil
                lastID = nil
            }
    }

    private func startIfNeeded(newID: ID) {
        if lastID == newID, task != nil { return }
        task?.cancel()
        task = Task { await action() }
        lastID = newID
    }
}

private struct OnChangeCompatModifier<V: Equatable>: ViewModifier {
    private let value: V
    private let action: @MainActor (V) -> Void

    fileprivate init(value: V, action: @escaping @MainActor (V) -> Void) {
        self.value = value
        self.action = action
    }

    fileprivate func body(content: Content) -> some View {
        content
            .background(OnChangeCompatObserver(value: value, action: action))
    }
}

private struct OnChangeCompatObserver<V: Equatable>: UIViewRepresentable {
    private let value: V
    private let action: @MainActor (V) -> Void

    fileprivate init(value: V, action: @escaping @MainActor (V) -> Void) {
        self.value = value
        self.action = action
    }

    fileprivate func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    fileprivate func makeUIView(context: Context) -> UIView { UIView(frame: .zero) }

    fileprivate func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.update(action: action)

        if let last = context.coordinator.lastValue {
            if last != value {
                context.coordinator.lastValue = value
                context.coordinator.schedule(value)
            }
        } else {
            context.coordinator.lastValue = value
        }
    }

    @MainActor
    fileprivate final class Coordinator {
        private var action: @MainActor (V) -> Void
        fileprivate var lastValue: V? = nil
        private var pendingValue: V? = nil
        private var isScheduled = false

        fileprivate init(action: @escaping @MainActor (V) -> Void) {
            self.action = action
        }

        fileprivate func update(action: @escaping @MainActor (V) -> Void) {
            self.action = action
        }

        fileprivate func schedule(_ value: V) {
            pendingValue = value
            guard !isScheduled else { return }
            isScheduled = true

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isScheduled = false
                guard let value = self.pendingValue else { return }
                self.pendingValue = nil
                self.action(value)
            }
        }
    }
}

extension Color {
    internal init(uiColorCompat uiColor: UIColor) {
        if #available(iOS 15, *) {
            self.init(uiColor: uiColor)
        } else {
            self.init(uiColor)
        }
    }
}
