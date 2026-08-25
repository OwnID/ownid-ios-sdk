import SwiftUI
import UIKit
import Combine

protocol Popup: View {
    associatedtype V: View

    func createContent() -> V
    func backgroundOverlayTapped()
}

extension Popup {
    func presentAsPopup() { OwnID.UISDK.PopupManager.presentPopup(OwnID.UISDK.AnyPopup(self)) }
    func dismiss() { OwnID.UISDK.PopupManager.dismissPopup() }

    var body: V { createContent() }
}

extension OwnID.UISDK {
    struct AnyPopup: Popup {
        private let popup: any Popup

        init(_ popup: some Popup) {
            self.popup = popup
        }

        func backgroundOverlayTapped() {
            popup.backgroundOverlayTapped()
        }
    }
}

extension OwnID.UISDK.AnyPopup {
    func createContent() -> some View {
        AnyView(popup)
    }
}

extension OwnID.UISDK {
    final class SliderViewController: UIViewController {
        var popup: AnyPopup!

        private enum LayoutConstants {
            static let maxSheetWidth: CGFloat = 480
        }

        private let overlayView = UIControl(frame: .zero)
        private let sheetContainerView = UIView(frame: .zero)
        private let layoutRelay = PopupLayoutRelay()
        private var hostingController: UIHostingController<PopupView<AnyPopup>>!
        private lazy var sheetHeightConstraint = sheetContainerView.heightAnchor.constraint(equalToConstant: 1)
        private var sheetBottomConstraint: NSLayoutConstraint!
        private var keyboardOverlap: CGFloat = 0
        private var isHeightUpdateScheduled = false
        private var isSizeTransitionInFlight = false

        override func viewDidLoad() {
            super.viewDidLoad()

            overlayView.backgroundColor = UIColor.black.withAlphaComponent(PopupViewContants.backgroundOpacity)
            overlayView.isAccessibilityElement = false
            overlayView.accessibilityElementsHidden = true
            overlayView.addTarget(self, action: #selector(backgroundTapped), for: .touchUpInside)
            overlayView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(overlayView)

            sheetContainerView.clipsToBounds = true
            sheetContainerView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(sheetContainerView)
            view.accessibilityViewIsModal = true

            let hostingController = UIHostingController(
                rootView: PopupView(content: popup, layoutRelay: layoutRelay)
            )
            hostingController.view.backgroundColor = .clear
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false
            addChild(hostingController)
            sheetContainerView.addSubview(hostingController.view)
            hostingController.didMove(toParent: self)
            self.hostingController = hostingController

            let preferredWidth = sheetContainerView.widthAnchor.constraint(equalTo: view.safeAreaLayoutGuide.widthAnchor)
            preferredWidth.priority = .defaultHigh
            sheetBottomConstraint = makeSheetBottomConstraint()

            NSLayoutConstraint.activate([
                overlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                overlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                overlayView.topAnchor.constraint(equalTo: view.topAnchor),
                overlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

                sheetContainerView.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
                sheetContainerView.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor),
                sheetContainerView.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor),
                sheetContainerView.widthAnchor.constraint(lessThanOrEqualToConstant: LayoutConstants.maxSheetWidth),
                preferredWidth,
                sheetBottomConstraint,
                sheetHeightConstraint,

                hostingController.view.leadingAnchor.constraint(equalTo: sheetContainerView.leadingAnchor),
                hostingController.view.trailingAnchor.constraint(equalTo: sheetContainerView.trailingAnchor),
                hostingController.view.topAnchor.constraint(equalTo: sheetContainerView.topAnchor),
                hostingController.view.bottomAnchor.constraint(equalTo: sheetContainerView.bottomAnchor),
            ])

            layoutRelay.onNeedsLayout = { [weak self] in
                self?.setNeedsSheetHeightUpdate()
            }
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            guard !isSizeTransitionInFlight else { return }
            updateSheetHeight()
        }

        override func viewWillTransition(
            to size: CGSize,
            with coordinator: UIViewControllerTransitionCoordinator
        ) {
            isSizeTransitionInFlight = true
            super.viewWillTransition(to: size, with: coordinator)
            coordinator.animate(alongsideTransition: nil) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isSizeTransitionInFlight = false
                    self.setNeedsSheetHeightUpdate()
                }
            }
        }

        override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
            return .allButUpsideDown
        }

        @objc
        private func backgroundTapped() {
            popup.backgroundOverlayTapped()
        }

        private func makeSheetBottomConstraint() -> NSLayoutConstraint {
            if #available(iOS 15.0, *) {
                view.keyboardLayoutGuide.followsUndockedKeyboard = false
                if #available(iOS 17.0, *) {
                    view.keyboardLayoutGuide.usesBottomSafeArea = false
                }
                return sheetContainerView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
            }

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(keyboardWillChangeFrame(_:)),
                name: UIResponder.keyboardWillChangeFrameNotification,
                object: nil
            )
            return sheetContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        }

        @objc
        private func keyboardWillChangeFrame(_ notification: Notification) {
            guard
                let userInfo = notification.userInfo,
                (userInfo[UIResponder.keyboardIsLocalUserInfoKey] as? Bool) != false,
                let frameValue = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue
            else {
                return
            }

            let coordinateSpace =
                (notification.object as? UIScreen)?.coordinateSpace
                ?? view.window?.screen.coordinateSpace
                ?? UIScreen.main.coordinateSpace
            let keyboardFrame = coordinateSpace.convert(frameValue.cgRectValue, to: view)
            let intersection = view.bounds.intersection(keyboardFrame)
            view.layoutIfNeeded()
            keyboardOverlap = max(intersection.height, 0)
            sheetBottomConstraint.constant = -keyboardOverlap
            hostingController.view.invalidateIntrinsicContentSize()
            updateSheetHeight()

            let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0
            let curve = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? 0
            UIView.animate(
                withDuration: duration,
                delay: 0,
                options: [UIView.AnimationOptions(rawValue: curve << 16), .beginFromCurrentState]
            ) { [weak self] in
                self?.view.layoutIfNeeded()
            }
        }

        private func setNeedsSheetHeightUpdate() {
            guard isViewLoaded, !isSizeTransitionInFlight, !isHeightUpdateScheduled else { return }
            isHeightUpdateScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isHeightUpdateScheduled = false
                self.hostingController.view.invalidateIntrinsicContentSize()
                self.view.setNeedsLayout()
                self.view.layoutIfNeeded()
                self.updateSheetHeight()
            }
        }

        private func updateSheetHeight() {
            guard !isSizeTransitionInFlight, hostingController != nil else { return }

            let width = sheetContainerView.bounds.width > 0
                ? sheetContainerView.bounds.width
                : min(view.safeAreaLayoutGuide.layoutFrame.width, LayoutConstants.maxSheetWidth)
            let keyboardTop: CGFloat
            if #available(iOS 15.0, *) {
                let guideTop = view.keyboardLayoutGuide.layoutFrame.minY
                keyboardTop = guideTop > 0 ? min(guideTop, view.bounds.height) : view.bounds.height
            } else {
                keyboardTop = view.bounds.height - keyboardOverlap
            }
            let maxHeight = max(keyboardTop - view.safeAreaInsets.top, 1)
            let fittingSize = hostingController.sizeThatFits(
                in: CGSize(width: width, height: maxHeight)
            )
            let height = min(max(ceil(fittingSize.height), 1), maxHeight)

            guard abs(sheetHeightConstraint.constant - height) > 0.5 else { return }
            sheetHeightConstraint.constant = height
        }
    }
    
    final class PopupManager {
        private static var currentViewController: UIViewController?
        
        static func presentPopup(_ popup: AnyPopup) {
            let viewController = SliderViewController()
            viewController.popup = popup
            viewController.view.backgroundColor = .clear
            viewController.modalPresentationStyle = .overCurrentContext
            currentViewController = viewController
            UIApplication.topViewController()?.present(viewController, animated: false)
        }
        
        static func dismissPopup(completion: (() -> Void)? = nil) {
            if currentViewController != nil {
                currentViewController?.dismiss(animated: false, completion: completion)
                currentViewController = nil
            } else {
                completion?()
            }
        }
    }
    
    private enum PopupViewContants {
        static let contentCornerRadius: CGFloat = 10.0
        static let animationResponse = 0.32
        static let animationDampingFraction = 1.0
        static let animationDuration = 0.32
        static let backgroundOpacity = 0.5
    }
    
    struct SliderBackground: ViewModifier {
        let colorScheme: ColorScheme

        func body(content: Content) -> some View {
            if #available(iOS 15.0, *) {
                if colorScheme == .dark {
                    content
                        .background(.regularMaterial)
                        .containerShape(RoundedCorner(radius: PopupViewContants.contentCornerRadius, corners: [.topLeft, .topRight]))
                } else {
                    content
                        .background(OwnID.Colors.sliderBackground)
                        .containerShape(RoundedCorner(radius: PopupViewContants.contentCornerRadius, corners: [.topLeft, .topRight]))
                }
            } else {
                if colorScheme == .dark {
                    content
                        .background(Blur(style: .dark)
                            .cornerRadius(PopupViewContants.contentCornerRadius, corners: [.topLeft, .topRight])
                            .ignoresSafeArea())
                } else {
                    content
                        .background(OwnID.Colors.sliderBackground
                            .cornerRadius(PopupViewContants.contentCornerRadius, corners: [.topLeft, .topRight])
                            .ignoresSafeArea())
                }
            }
        }
    }
    
    final class PopupLayoutRelay {
        var onNeedsLayout: (() -> Void)?

        func setNeedsLayout() {
            onNeedsLayout?()
        }
    }

    struct PopupLayoutInvalidator: UIViewRepresentable {
        let onNeedsLayout: () -> Void

        func makeUIView(context: Context) -> UIView {
            let view = UIView(frame: .zero)
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
            return view
        }

        func updateUIView(_ uiView: UIView, context: Context) {
            onNeedsLayout()
        }
    }

    struct PopupView<Content: Popup>: View {
        let content: Content
        let layoutRelay: PopupLayoutRelay

        @Environment(\.colorScheme) var colorScheme

        var body: some View {
            content
                .sliderBackground(colorScheme: colorScheme)
                .background(PopupLayoutInvalidator(onNeedsLayout: layoutRelay.setNeedsLayout))
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .transition(.move(edge: .top))
        }
    }
}

private extension View {
    func sliderBackground(colorScheme: ColorScheme) -> some View {
        modifier(OwnID.UISDK.SliderBackground(colorScheme: colorScheme))
    }
}
