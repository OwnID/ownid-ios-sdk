@_spi(OwnIDInternal) import OwnIDCore
import SwiftUI
import UIKit

private struct BottomSheetSurface: View {
    @ObservedObject private var themeStore: OwnIDThemeStore
    @ObservedObject private var containerController: OwnIDUIContainerController
    @Environment(\.colorScheme) private var colorScheme

    private let content: AnyView
    private let layoutRelay: BottomSheetLayoutRelay

    init(
        themeStore: OwnIDThemeStore,
        containerController: OwnIDUIContainerController,
        content: AnyView,
        layoutRelay: BottomSheetLayoutRelay
    ) {
        self._themeStore = ObservedObject(wrappedValue: themeStore)
        self._containerController = ObservedObject(wrappedValue: containerController)
        self.content = content
        self.layoutRelay = layoutRelay
    }

    var body: some View {
        let resolvedHostedTheme = themeStore.theme ?? OwnIDTheme.sdkDefault(for: colorScheme)
        let surfaceColor = resolvedHostedTheme.colors.surface
        content
            .background(surfaceColor)
            .background(BottomSheetLayoutInvalidator { layoutRelay.setNeedsLayout() })
            .disableHostedKeyboardAvoidance()
            .clipShape(TopRoundedCorners(radius: 10))
            .contentShape(TopRoundedCorners(radius: 10))
            .environment(\.ownIDTheme, resolvedHostedTheme)
            .environment(\.ownIDSuppressTextInputFocus, containerController.isClosing)
            .tintCompat(resolvedHostedTheme.colors.primary)
    }
}

extension View {
    @ViewBuilder
    fileprivate func disableHostedKeyboardAvoidance() -> some View {
        if #available(iOS 14.0, *) {
            ignoresSafeArea(.keyboard, edges: .bottom)
        } else {
            self
        }
    }
}

@MainActor
private final class BottomSheetLayoutRelay {
    fileprivate var onNeedsLayout: (@MainActor () -> Void)?

    @MainActor
    fileprivate func setNeedsLayout() {
        onNeedsLayout?()
    }
}

private struct BottomSheetLayoutInvalidator: UIViewRepresentable {
    typealias UIViewType = UIView

    private let onNeedsLayout: @MainActor () -> Void

    fileprivate init(onNeedsLayout: @escaping @MainActor () -> Void) {
        self.onNeedsLayout = onNeedsLayout
    }

    func makeUIView(context: UIViewRepresentableContext<BottomSheetLayoutInvalidator>) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: UIViewRepresentableContext<BottomSheetLayoutInvalidator>) {
        onNeedsLayout()
    }
}

private struct TopRoundedCorners: Shape {
    private let radius: CGFloat

    init(radius: CGFloat) {
        self.radius = radius
    }

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: [.topLeft, .topRight],
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

internal final class BottomSheetViewController: UIViewController {
    private enum LayoutConstants {
        static let maxSheetWidth: CGFloat = 480
    }

    private enum AnimationConstants {
        static let duration: TimeInterval = 0.28
        static let dimmedOverlayAlpha: CGFloat = 0.5
        static let dragDismissDistanceRatio: CGFloat = 0.33
        static let dragDismissVelocity: CGFloat = 900
        static let dragFadeDistance: CGFloat = 240
        static let dragResetDuration: TimeInterval = 0.22
        static let dragResetDamping: CGFloat = 0.86
    }

    private let containerController: OwnIDUIContainerController
    private let hostingController: UIHostingController<BottomSheetSurface>

    private let overlayView = UIControl(frame: .zero)
    private let sheetContainerView = UIView(frame: .zero)
    private lazy var sheetHeightConstraint = sheetContainerView.heightAnchor.constraint(equalToConstant: 1)
    private var sheetBottomConstraint: NSLayoutConstraint!
    private var keyboardOverlap: CGFloat = 0
    private var isSheetHeightUpdateScheduled = false
    private var panStartTouchY: CGFloat?
    private var isInteractiveDismissing = false

    private var hasAppeared = false
    private var hasAnimatedIn = false
    private var isDismissalExpected = false
    private var isDismissalAnimating = false
    private var pendingDismissCompletion: (@MainActor () -> Void)?

    internal var onDidOpen: (@MainActor () -> Void)?
    internal var onDidDisappearUnexpectedly: (@MainActor () -> Void)?

    internal init(
        content: AnyView,
        themeStore: OwnIDThemeStore,
        containerController: OwnIDUIContainerController
    ) {
        self.containerController = containerController
        let layoutRelay = BottomSheetLayoutRelay()
        self.hostingController = UIHostingController(
            rootView: BottomSheetSurface(
                themeStore: themeStore,
                containerController: containerController,
                content: content,
                layoutRelay: layoutRelay
            )
        )
        super.init(nibName: nil, bundle: nil)
        layoutRelay.onNeedsLayout = { [weak self] in
            self?.setNeedsSheetHeightUpdate()
        }

        if #available(iOS 16.0, *) {
            hostingController.sizingOptions = [.preferredContentSize, .intrinsicContentSize]
        }

        modalPresentationStyle = .overFullScreen
        view.backgroundColor = .clear
        view.accessibilityViewIsModal = true
    }

    @available(*, unavailable)
    internal required init?(coder: NSCoder) {
        return nil
    }

    internal override func viewDidLoad() {
        super.viewDidLoad()

        overlayView.backgroundColor = .black
        overlayView.alpha = 0
        overlayView.isAccessibilityElement = false
        overlayView.accessibilityElementsHidden = true
        overlayView.addTarget(self, action: #selector(backgroundTapped), for: .touchUpInside)

        view.addSubview(overlayView)
        view.addSubview(sheetContainerView)
        let sheetPanGesture = UIPanGestureRecognizer(target: self, action: #selector(sheetPanned(_:)))
        sheetPanGesture.delegate = self
        sheetContainerView.addGestureRecognizer(sheetPanGesture)

        overlayView.translatesAutoresizingMaskIntoConstraints = false
        sheetContainerView.translatesAutoresizingMaskIntoConstraints = false
        let sheetWidthConstraint = sheetContainerView.widthAnchor.constraint(equalTo: view.safeAreaLayoutGuide.widthAnchor)
        sheetWidthConstraint.priority = .defaultHigh
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
            sheetWidthConstraint,
            sheetBottomConstraint,
            sheetHeightConstraint,
        ])

        hostingController.view.backgroundColor = .clear
        hostingController.view.setContentHuggingPriority(.required, for: .vertical)
        hostingController.view.setContentCompressionResistancePriority(.required, for: .vertical)

        addChild(hostingController)
        sheetContainerView.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: sheetContainerView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: sheetContainerView.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: sheetContainerView.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: sheetContainerView.bottomAnchor),
        ])

        isModalInPresentation = true
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    internal override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateSheetHeightIfNeeded()
    }

    internal override func preferredContentSizeDidChange(forChildContentContainer container: any UIContentContainer) {
        super.preferredContentSizeDidChange(forChildContentContainer: container)
        guard container === hostingController else { return }
        setNeedsSheetHeightUpdate()
    }

    internal override func systemLayoutFittingSizeDidChange(forChildContentContainer container: any UIContentContainer) {
        super.systemLayoutFittingSizeDidChange(forChildContentContainer: container)
        guard container === hostingController else { return }
        setNeedsSheetHeightUpdate()
    }

    internal override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hasAppeared = true
        animateInIfNeeded()
    }

    internal override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        invokeDismissCompletionIfNeeded()
        guard hasAppeared else { return }

        guard !isDismissalExpected else {
            isDismissalExpected = false
            isDismissalAnimating = false
            return
        }

        let isLeavingPresentationHierarchy =
            isBeingDismissed || navigationController?.isBeingDismissed == true || presentingViewController == nil
        guard isLeavingPresentationHierarchy else { return }
        containerController.markClosed()
        onDidDisappearUnexpectedly?()
    }

    @MainActor
    internal func requestDismiss(completion: @escaping @MainActor () -> Void) {
        guard !isDismissalExpected else { return }
        isDismissalExpected = true
        pendingDismissCompletion = completion

        guard isViewLoaded, hasAppeared, hasAnimatedIn else {
            dismiss(animated: false) { [weak self] in
                self?.invokeDismissCompletionIfNeeded()
            }
            return
        }

        animateOutAndDismissIfNeeded()
    }

    @MainActor
    @objc
    private func backgroundTapped() {
        guard !isDismissalExpected else { return }
        containerController.close()
    }

    internal override func accessibilityPerformEscape() -> Bool {
        guard !isDismissalExpected else { return false }
        containerController.close()
        return true
    }

    @MainActor
    @objc
    private func sheetPanned(_ recognizer: UIPanGestureRecognizer) {
        guard canInteractivelyDismiss else { return }

        let translationY = interactiveDismissOffset(for: max(recognizer.translation(in: view).y, 0))
        let velocityY = recognizer.velocity(in: view).y
        let locationY = recognizer.location(in: view).y

        switch recognizer.state {
        case .began:
            isInteractiveDismissing = true
            panStartTouchY = locationY - translationY
            applyInteractiveDismissOffset(translationY)
        case .changed:
            applyInteractiveDismissOffset(translationY)
        case .ended:
            panStartTouchY = nil
            if shouldFinishInteractiveDismiss(translationY: translationY, velocityY: velocityY) {
                isInteractiveDismissing = false
                containerController.close()
            } else {
                resetInteractiveDismissOffset()
            }
        case .cancelled, .failed:
            panStartTouchY = nil
            resetInteractiveDismissOffset()
        default:
            break
        }
    }

    private func animateInIfNeeded() {
        guard !hasAnimatedIn else { return }
        hasAnimatedIn = true

        view.layoutIfNeeded()
        sheetContainerView.transform = dismissedTransform

        UIView.animate(
            withDuration: AnimationConstants.duration,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState]
        ) { [weak self] in
            guard let self else { return }
            self.overlayView.alpha = AnimationConstants.dimmedOverlayAlpha
            self.sheetContainerView.transform = .identity
        } completion: { [weak self] finished in
            guard let self, finished else { return }
            self.onDidOpen?()
            self.containerController.markOpened()
            if self.isDismissalExpected {
                self.animateOutAndDismissIfNeeded()
            }
        }
    }

    private func animateOutAndDismissIfNeeded() {
        guard !isDismissalAnimating else { return }
        isDismissalAnimating = true
        view.endEditing(true)

        view.layoutIfNeeded()
        UIView.animate(
            withDuration: AnimationConstants.duration,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState]
        ) { [weak self] in
            guard let self else { return }
            self.overlayView.alpha = 0
            self.sheetContainerView.transform = dismissedTransform
        } completion: { [weak self] _ in
            self?.dismiss(animated: false)
        }
    }

    private func invokeDismissCompletionIfNeeded() {
        let dismissCompletion = pendingDismissCompletion
        pendingDismissCompletion = nil
        dismissCompletion?()
    }

    private func applyInteractiveDismissOffset(_ offset: CGFloat) {
        let progress = min(offset / AnimationConstants.dragFadeDistance, 1)
        sheetContainerView.transform = CGAffineTransform(translationX: 0, y: offset)
        overlayView.alpha = AnimationConstants.dimmedOverlayAlpha * (1 - progress)
    }

    private func interactiveDismissOffset(for offset: CGFloat) -> CGFloat {
        BottomSheetLayoutMetrics.interactiveDismissOffset(
            proposedOffset: offset,
            isKeyboardVisible: isKeyboardVisible,
            panStartTouchY: panStartTouchY,
            currentKeyboardTop: currentKeyboardTop
        )
    }

    private func shouldFinishInteractiveDismiss(translationY: CGFloat, velocityY: CGFloat) -> Bool {
        translationY > sheetContainerView.bounds.height * AnimationConstants.dragDismissDistanceRatio
            || velocityY > AnimationConstants.dragDismissVelocity
    }

    private func resetInteractiveDismissOffset() {
        guard canInteractivelyDismiss else { return }

        UIView.animate(
            withDuration: AnimationConstants.dragResetDuration,
            delay: 0,
            usingSpringWithDamping: AnimationConstants.dragResetDamping,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) { [weak self] in
            guard let self else { return }
            self.sheetContainerView.transform = .identity
            self.overlayView.alpha = AnimationConstants.dimmedOverlayAlpha
        } completion: { [weak self] _ in
            self?.isInteractiveDismissing = false
        }
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
        guard !isDismissalExpected, !isDismissalAnimating else { return }
        guard
            let userInfo = notification.userInfo,
            let frameValue = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue
        else {
            return
        }

        let coordinateSpace =
            (notification.object as? UIScreen)?.coordinateSpace
            ?? view.window?.screen.coordinateSpace
            ?? UIScreen.main.coordinateSpace
        let keyboardFrame = coordinateSpace.convert(frameValue.cgRectValue, to: view)
        keyboardOverlap = BottomSheetLayoutMetrics.keyboardOverlap(
            viewBounds: view.bounds,
            keyboardFrameInView: keyboardFrame
        )
        sheetBottomConstraint.constant = -keyboardOverlap
        setNeedsSheetHeightUpdate()
    }

    @MainActor
    fileprivate func setNeedsSheetHeightUpdate() {
        guard !isDismissalExpected, !isDismissalAnimating else { return }
        guard isViewLoaded else { return }
        guard !isInteractiveDismissing else { return }

        hostingController.view.invalidateIntrinsicContentSize()
        hostingController.view.setNeedsLayout()
        sheetContainerView.setNeedsLayout()
        view.setNeedsLayout()

        guard !isSheetHeightUpdateScheduled else { return }
        isSheetHeightUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isSheetHeightUpdateScheduled = false
            self.view.layoutIfNeeded()
            self.updateSheetHeightIfNeeded()
        }
    }

    private func updateSheetHeightIfNeeded() {
        guard !isDismissalExpected, !isDismissalAnimating else { return }
        guard !isInteractiveDismissing else { return }

        let fittingSize = hostingController.sizeThatFits(in: CGSize(width: sheetFittingWidth, height: maxSheetHeight))
        let resolvedHeight = BottomSheetLayoutMetrics.resolvedSheetHeight(
            fittingHeight: fittingSize.height,
            maxSheetHeight: maxSheetHeight
        )

        guard abs(sheetHeightConstraint.constant - resolvedHeight) > 0.5 else { return }
        sheetHeightConstraint.constant = resolvedHeight
    }

    private var sheetFittingWidth: CGFloat {
        BottomSheetLayoutMetrics.sheetFittingWidth(
            containerWidth: sheetContainerView.bounds.width,
            viewWidth: view.bounds.width,
            maxSheetWidth: LayoutConstants.maxSheetWidth
        )
    }

    private var maxSheetHeight: CGFloat {
        if #available(iOS 15.0, *) {
            return BottomSheetLayoutMetrics.maxSheetHeight(
                viewHeight: view.bounds.height,
                safeAreaTop: view.safeAreaInsets.top,
                keyboardTop: currentKeyboardTop
            )
        }
        return BottomSheetLayoutMetrics.maxSheetHeight(
            viewHeight: view.bounds.height,
            safeAreaTop: view.safeAreaInsets.top,
            keyboardOverlap: keyboardOverlap
        )
    }

    private var currentKeyboardTop: CGFloat {
        if #available(iOS 15.0, *) {
            return BottomSheetLayoutMetrics.keyboardTop(
                viewHeight: view.bounds.height,
                layoutGuideMinY: view.keyboardLayoutGuide.layoutFrame.minY
            )
        }
        return BottomSheetLayoutMetrics.keyboardTop(viewHeight: view.bounds.height, keyboardOverlap: keyboardOverlap)
    }

    private var isKeyboardVisible: Bool {
        BottomSheetLayoutMetrics.isKeyboardVisible(
            currentKeyboardTop: currentKeyboardTop,
            viewHeight: view.bounds.height,
            safeAreaBottom: view.safeAreaInsets.bottom
        )
    }

    private var dismissedTransform: CGAffineTransform {
        CGAffineTransform(
            translationX: 0,
            y: BottomSheetLayoutMetrics.dismissedTranslationY(
                sheetHeight: sheetContainerView.bounds.height,
                safeAreaBottom: view.safeAreaInsets.bottom
            )
        )
    }

    private var canInteractivelyDismiss: Bool {
        hasAppeared && hasAnimatedIn && !isDismissalExpected && !isDismissalAnimating
    }

    internal override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }
}

extension BottomSheetViewController: UIGestureRecognizerDelegate {
    internal func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard
            gestureRecognizer.view === sheetContainerView,
            let panGesture = gestureRecognizer as? UIPanGestureRecognizer,
            canInteractivelyDismiss
        else {
            return false
        }

        let velocity = panGesture.velocity(in: view)
        return velocity.y > 0 && abs(velocity.y) > abs(velocity.x)
    }
}

internal enum BottomSheetLayoutMetrics {
    static let keyboardBoundaryPadding: CGFloat = 1
    static let keyboardVisibilityTolerance: CGFloat = 0.5
    static let dismissedTranslationPadding: CGFloat = 24

    static func keyboardOverlap(viewBounds: CGRect, keyboardFrameInView: CGRect) -> CGFloat {
        let intersection = viewBounds.intersection(keyboardFrameInView)
        return intersection.isNull ? 0 : intersection.height
    }

    static func keyboardTop(viewHeight: CGFloat, layoutGuideMinY: CGFloat) -> CGFloat {
        layoutGuideMinY > 0 ? layoutGuideMinY : viewHeight
    }

    static func keyboardTop(viewHeight: CGFloat, keyboardOverlap: CGFloat) -> CGFloat {
        max(viewHeight - keyboardOverlap, 0)
    }

    static func maxSheetHeight(viewHeight: CGFloat, safeAreaTop: CGFloat, keyboardTop: CGFloat) -> CGFloat {
        max((keyboardTop > 0 ? keyboardTop : viewHeight) - safeAreaTop, 1)
    }

    static func maxSheetHeight(viewHeight: CGFloat, safeAreaTop: CGFloat, keyboardOverlap: CGFloat) -> CGFloat {
        max(viewHeight - safeAreaTop - keyboardOverlap, 1)
    }

    static func sheetFittingWidth(containerWidth: CGFloat, viewWidth: CGFloat, maxSheetWidth: CGFloat) -> CGFloat {
        containerWidth > 0 ? containerWidth : min(viewWidth, maxSheetWidth)
    }

    static func resolvedSheetHeight(fittingHeight: CGFloat, maxSheetHeight: CGFloat) -> CGFloat {
        min(max(fittingHeight.rounded(.up), 1), maxSheetHeight)
    }

    static func isKeyboardVisible(currentKeyboardTop: CGFloat, viewHeight: CGFloat, safeAreaBottom: CGFloat) -> Bool {
        currentKeyboardTop < viewHeight - safeAreaBottom - keyboardVisibilityTolerance
    }

    static func interactiveDismissOffset(
        proposedOffset: CGFloat,
        isKeyboardVisible: Bool,
        panStartTouchY: CGFloat?,
        currentKeyboardTop: CGFloat
    ) -> CGFloat {
        guard isKeyboardVisible, let panStartTouchY else { return proposedOffset }
        return min(proposedOffset, max(currentKeyboardTop - panStartTouchY - keyboardBoundaryPadding, 0))
    }

    static func dismissedTranslationY(sheetHeight: CGFloat, safeAreaBottom: CGFloat) -> CGFloat {
        max(sheetHeight, 1) + safeAreaBottom + dismissedTranslationPadding
    }
}
