import SwiftUI
import UIKit

@MainActor
internal final class WidgetWindowAttachment {
    private weak var windowReference: UIWindow?

    fileprivate init(window: UIWindow) {
        self.windowReference = window
    }

    internal var window: UIWindow? {
        windowReference
    }

    fileprivate func invalidate() {
        windowReference = nil
    }
}

@MainActor
internal struct WidgetWindowReader: UIViewRepresentable {
    internal typealias UIViewType = UIView

    @Binding private var attachment: WidgetWindowAttachment?

    internal init(attachment: Binding<WidgetWindowAttachment?>) {
        self._attachment = attachment
    }

    internal func makeUIView(context: UIViewRepresentableContext<WidgetWindowReader>) -> UIView {
        let probe = ProbeView()
        configure(probe)
        return probe
    }

    internal func updateUIView(_ view: UIView, context: UIViewRepresentableContext<WidgetWindowReader>) {
        guard let probe = view as? ProbeView else { return }
        configure(probe)
    }

    internal static func dismantleUIView(_ view: UIView, coordinator: ()) {
        (view as? ProbeView)?.dismantle()
    }

    private func configure(_ probe: ProbeView) {
        let attachment = $attachment
        probe.onAttachmentChange = { previousAttachment, nextAttachment in
            Task { @MainActor in
                if let nextAttachment {
                    guard nextAttachment.window != nil else { return }
                    if attachment.wrappedValue !== nextAttachment {
                        attachment.wrappedValue = nextAttachment
                    }
                } else if let previousAttachment, attachment.wrappedValue === previousAttachment {
                    // Do not clear a newer attachment created after this view left its previous window.
                    attachment.wrappedValue = nil
                }
            }
        }
    }

    @MainActor
    private final class ProbeView: UIView {
        fileprivate var onAttachmentChange: ((WidgetWindowAttachment?, WidgetWindowAttachment?) -> Void)?
        private var currentAttachment: WidgetWindowAttachment?

        internal init() {
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
            accessibilityElementsHidden = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is unavailable")
        }

        override internal func didMoveToWindow() {
            super.didMoveToWindow()
            guard onAttachmentChange != nil else { return }
            replaceAttachment(window.map { WidgetWindowAttachment(window: $0) })
        }

        fileprivate func dismantle() {
            replaceAttachment(nil)
            onAttachmentChange = nil
        }

        private func replaceAttachment(_ nextAttachment: WidgetWindowAttachment?) {
            let previousAttachment = currentAttachment
            previousAttachment?.invalidate()
            currentAttachment = nextAttachment
            onAttachmentChange?(previousAttachment, nextAttachment)
        }
    }
}
