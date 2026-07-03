@_spi(OwnIDInternal) import OwnIDCore
import SwiftUI

/// Controls where the OwnID Boost button appears relative to the "or" separator.
public enum OwnIDBoostButtonPosition {
    /// Shows the OwnID Boost button before the "or" separator.
    case start

    /// Shows the OwnID Boost button after the "or" separator.
    case end
}

/// Displays the OwnID Boost button UI.
///
/// The component arranges an icon button, optional "or" separator, and optional completion checkmark. Use it when the
/// app owns the surrounding action but wants the standard OwnID button row, localized separator text, theme propagation,
/// and accessibility label handoff.
///
/// The caller owns `onClick` and any work it starts. The default icon button invokes `onClick` only while enabled and
/// ignores rapid repeat taps. By default the button is disabled while `isBusy` is true. When `showSpinner` is true,
/// `isBusy` is forwarded to the icon-button slot so the default button replaces the icon with ``OwnIDSpinnerView``.
///
/// `widgetStrings` supplies the visible separator text and the accessibility label passed to the icon-button slot.
/// Custom icon-button slots must apply the received accessibility label to the interactive element. The default
/// checkmark is decorative; expose completion through surrounding UI state when the app needs an accessibility
/// announcement.
///
/// Pass `theme:` when this button should use a specific OwnID theme instead of the current SwiftUI environment. The
/// row has a default minimum height of 44 points; custom slots should keep a comparable control size and semantics.
public struct OwnIDBoostButton<IconButton: View, OrText: View, Checkmark: View>: View {
    @Environment(\.ownIDTheme) private var ownIDTheme
    @Environment(\.colorScheme) private var colorScheme
    @State private var resolvedWidgetStrings: BoostWidgetStrings? = nil
    @State private var actionThrottler = UserActionThrottler()

    private let instanceName: InstanceName
    private let isBusy: Bool
    private let position: OwnIDBoostButtonPosition
    private let enabled: Bool?
    private let showSpinner: Bool
    private let theme: OwnIDTheme?
    private let finished: Bool
    private let widgetStrings: BoostWidgetStrings?
    private let onClick: () -> Void

    private let iconButton: (_ isBusy: Bool, _ isEnabled: Bool, _ action: @escaping () -> Void, _ accessibilityLabel: String) -> IconButton
    private let orText: (String) -> OrText
    private let checkmark: () -> Checkmark

    /// Creates an OwnID button row with fully custom subviews.
    ///
    /// Use this initializer when you want complete control over the button, "or" separator, and completion indicator
    /// while keeping the standard OwnID row layout contract.
    ///
    /// - Parameters:
    ///   - onClick: Action invoked when the icon button is activated.
    ///   - isBusy: Whether the owning action is in progress.
    ///   - instanceName: Instance used for default string resolution when `widgetStrings` is `nil`.
    ///   - position: Whether the OwnID Boost button appears before or after the "or" separator. Defaults to
    ///     ``OwnIDBoostButtonPosition/start``.
    ///   - enabled: Whether the icon button accepts input. Defaults to `nil`, which resolves to `!isBusy`.
    ///   - finished: Whether to show the completion checkmark overlay.
    ///   - showSpinner: Whether the icon-button slot receives a busy state when `isBusy` is true.
    ///   - theme: Optional OwnID theme for this button. When `nil`, the button uses the current OwnID theme.
    ///   - widgetStrings: Optional explicit strings used for the button label, the "or" text, and accessibility.
    ///     When `nil`, the button starts from ``BoostWidgetStrings/default`` and automatically uses localized widget
    ///     strings for `instanceName` when they become available.
    ///   - iconButton: Custom interactive button content. Apply the received accessibility label to the control.
    ///   - orText: Custom "or" separator content.
    ///   - checkmark: Custom completion badge content.
    public init(
        onClick: @escaping () -> Void,
        isBusy: Bool,
        instanceName: InstanceName,
        position: OwnIDBoostButtonPosition = .start,
        enabled: Bool? = nil,
        finished: Bool,
        showSpinner: Bool,
        theme: OwnIDTheme? = nil,
        widgetStrings: BoostWidgetStrings? = nil,
        @ViewBuilder iconButton:
            @escaping (_ isBusy: Bool, _ isEnabled: Bool, _ action: @escaping () -> Void, _ accessibilityLabel: String) -> IconButton,
        @ViewBuilder orText: @escaping (String) -> OrText,
        @ViewBuilder checkmark: @escaping () -> Checkmark
    ) {
        self.onClick = onClick
        self.instanceName = instanceName
        self.isBusy = isBusy
        self.position = position
        self.enabled = enabled
        self.finished = finished
        self.showSpinner = showSpinner
        self.theme = theme
        self.widgetStrings = widgetStrings
        self.iconButton = iconButton
        self.orText = orText
        self.checkmark = checkmark
    }

    public var body: some View {
        let resolvedTheme = theme ?? ownIDTheme ?? OwnIDTheme.capture(colorScheme: colorScheme)
        let currentWidgetStrings = widgetStrings ?? resolvedWidgetStrings ?? .default
        let iconButtonBusy = showSpinner && isBusy
        let resolvedEnabled = enabled ?? !isBusy
        let throttledOnClick = { actionThrottler.processAction { onClick() } }

        HStack(alignment: .center, spacing: 8) {
            switch position {
            case .start:
                boostButton(
                    isBusy: iconButtonBusy,
                    isEnabled: resolvedEnabled,
                    action: throttledOnClick,
                    accessibilityLabel: currentWidgetStrings.skipPassword
                )
                orText(currentWidgetStrings.or)
            case .end:
                orText(currentWidgetStrings.or)
                boostButton(
                    isBusy: iconButtonBusy,
                    isEnabled: resolvedEnabled,
                    action: throttledOnClick,
                    accessibilityLabel: currentWidgetStrings.skipPassword
                )
            }
        }
        .frame(minHeight: 44, idealHeight: 44)
        .environment(\.ownIDTheme, resolvedTheme)
        .tintCompat(resolvedTheme.colors.primary)
        .boostWidgetStrings(
            instanceName: instanceName,
            widgetStrings: widgetStrings,
            resolvedWidgetStrings: $resolvedWidgetStrings
        )
    }

    @ViewBuilder
    private func boostButton(isBusy: Bool, isEnabled: Bool, action: @escaping () -> Void, accessibilityLabel: String) -> some View {
        iconButton(isBusy, isEnabled, action, accessibilityLabel)
            .overlayCompat(alignment: .topTrailing) {
                if finished {
                    GeometryReader { proxy in
                        let side = min(proxy.size.width, proxy.size.height)
                        let badgeContainerSize = side * 0.5
                        let badgeSize = badgeContainerSize * 0.75

                        ZStack {
                            checkmark()
                                .frame(width: badgeSize, height: badgeSize)
                        }
                        .frame(width: badgeContainerSize, height: badgeContainerSize)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .scale))
                    }
                }
            }
            .animationCompat(.default, value: finished)
    }
}

extension OwnIDBoostButton where IconButton == OwnIDIconButtonView<RoundedRectangle>, OrText == Text, Checkmark == OwnIDCheckmarkView {

    /// Creates an OwnID button row using the default OwnID components.
    ///
    /// - Parameters:
    ///   - onClick: Action invoked when the icon button is activated.
    ///   - isBusy: Whether the owning action is in progress.
    ///   - instanceName: Instance used for default string resolution when `widgetStrings` is `nil`.
    ///   - position: Whether the OwnID Boost button appears before or after the "or" separator. Defaults to
    ///     ``OwnIDBoostButtonPosition/start``.
    ///   - enabled: Whether the icon button accepts input. Defaults to `nil`, which resolves to `!isBusy`.
    ///   - finished: Whether to show a completion checkmark overlay. Defaults to `false`.
    ///   - showSpinner: Whether the icon button should show a spinner when busy. Defaults to `true`.
    ///   - theme: Optional explicit OwnID theme for this widget. When `nil`, the widget uses the current
    ///     ``EnvironmentValues/ownIDTheme`` or captures the current SwiftUI color scheme and primary accent color.
    ///   - widgetStrings: Optional explicit strings. When omitted, the button starts from
    ///     ``BoostWidgetStrings/default`` and then uses localized widget strings for `instanceName` when they become
    ///     available.
    public init(
        onClick: @escaping () -> Void,
        isBusy: Bool,
        instanceName: InstanceName = .default,
        position: OwnIDBoostButtonPosition = .start,
        enabled: Bool? = nil,
        finished: Bool = false,
        showSpinner: Bool = true,
        theme: OwnIDTheme? = nil,
        widgetStrings: BoostWidgetStrings? = nil,
    ) {
        self.init(
            onClick: onClick,
            isBusy: isBusy,
            instanceName: instanceName,
            position: position,
            enabled: enabled,
            finished: finished,
            showSpinner: showSpinner,
            theme: theme,
            widgetStrings: widgetStrings,
            iconButton: { isBusy, isEnabled, action, accessibilityLabel in
                OwnIDIconButtonView(isBusy: isBusy, accessibilityLabel: accessibilityLabel, isEnabled: isEnabled, action: action)
            },
            orText: { Text($0) },
            checkmark: { OwnIDCheckmarkView() }
        )
    }
}

extension OwnIDBoostButton {

    /// Returns a copy that uses custom "or" separator content.
    ///
    /// The closure receives the resolved localized separator text. Pass text that remains understandable when the
    /// separator is read between the app's password UI and the OwnID button.
    public func orText<CustomOrText: View>(
        @ViewBuilder _ customOrText: @escaping (String) -> CustomOrText
    ) -> OwnIDBoostButton<IconButton, CustomOrText, Checkmark> {
        .init(
            onClick: onClick,
            isBusy: isBusy,
            instanceName: instanceName,
            position: position,
            enabled: enabled,
            finished: finished,
            showSpinner: showSpinner,
            theme: theme,
            widgetStrings: widgetStrings,
            iconButton: iconButton,
            orText: customOrText,
            checkmark: checkmark
        )
    }

    /// Returns a copy that uses a custom icon-button view.
    ///
    /// The closure receives the busy state, enabled state, tap action, and resolved accessibility label. The custom
    /// view owns its control sizing, disabled behavior, progress presentation, and accessibility label.
    public func iconButton<CustomIconButton: View>(
        @ViewBuilder _ customIconButton:
            @escaping (_ isBusy: Bool, _ isEnabled: Bool, _ action: @escaping () -> Void, _ accessibilityLabel: String) -> CustomIconButton
    ) -> OwnIDBoostButton<CustomIconButton, OrText, Checkmark> {
        .init(
            onClick: onClick,
            isBusy: isBusy,
            instanceName: instanceName,
            position: position,
            enabled: enabled,
            finished: finished,
            showSpinner: showSpinner,
            theme: theme,
            widgetStrings: widgetStrings,
            iconButton: customIconButton,
            orText: orText,
            checkmark: checkmark
        )
    }

    /// Returns a copy that uses a custom completion-checkmark view.
    ///
    /// The default completion badge is decorative. Custom completion content should add accessibility semantics only
    /// when the surrounding UI does not already announce completion.
    public func checkmark<CustomCheckmark: View>(
        @ViewBuilder _ customCheckmark: @escaping () -> CustomCheckmark
    ) -> OwnIDBoostButton<IconButton, OrText, CustomCheckmark> {
        .init(
            onClick: onClick,
            isBusy: isBusy,
            instanceName: instanceName,
            position: position,
            enabled: enabled,
            finished: finished,
            showSpinner: showSpinner,
            theme: theme,
            widgetStrings: widgetStrings,
            iconButton: iconButton,
            orText: orText,
            checkmark: customCheckmark
        )
    }
}

extension View {
    @ViewBuilder
    func boostWidgetStrings(
        instanceName: InstanceName,
        widgetStrings: BoostWidgetStrings?,
        resolvedWidgetStrings: Binding<BoostWidgetStrings?>
    ) -> some View {
        if widgetStrings != nil {
            self
        } else {
            self.taskCompat(id: "OwnIDBoostWidgetStrings.\(instanceName.value)") {
                var activeStringsTask: Task<Void, Never>? = nil
                defer { activeStringsTask?.cancel() }

                for await instanceContainer in OwnID.getInstanceContainerStream(instanceName) {
                    if Task.isCancelled { break }

                    activeStringsTask?.cancel()
                    activeStringsTask = nil

                    guard let instanceContainer else {
                        resolvedWidgetStrings.wrappedValue = nil
                        continue
                    }

                    guard let stringsProvider = instanceContainer.getOrNil(type: (any BoostWidgetStringsProvider).self) else {
                        resolvedWidgetStrings.wrappedValue = nil
                        instanceContainer.getOrNil(type: OwnIDLogRouter.self)?.logW(
                            source: Self.self,
                            prefix: "body",
                            message: "No BoostWidgetStringsProvider found for \(instanceName.value)"
                        )
                        continue
                    }

                    activeStringsTask = Task { @MainActor in
                        for await newStrings in stringsProvider.getStrings(params: BoostWidgetStringsParams()).compactMap({ $0 }) {
                            if Task.isCancelled { break }
                            resolvedWidgetStrings.wrappedValue = newStrings
                        }
                    }
                }
            }
        }
    }
}
