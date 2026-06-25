@_spi(OwnIDInternal) import OwnIDCore
import SwiftUI

/// Displays the OwnID Boost create-passkey widget.
///
/// Add this widget to a sign-up or account screen to let the user create a passkey with OwnID. Tapping the widget
/// starts the Boost create-passkey flow with the widget-button source.
/// The SDK owns starting and settling the flow; the app owns any session, navigation, registration, or error UI changes
/// it performs from the callbacks.
///
/// A create-passkey result calls `onNewPasskey` and shows the checkmark state. A login result calls `onLogin`. User
/// or business cancellation calls `onCancel`. Flow start failures and terminal failures call `onError` with
/// ``BoostCreatePasskeyFlowFailure``. When the visible checkmark state is cleared because the login ID no longer
/// matches the in-memory create-passkey result, `onReset` is called. While a flow is running, repeated taps are ignored
/// and the default icon button is disabled. `showSpinner` controls whether the busy state is shown as a spinner; it
/// does not make a running flow accept another tap.
///
/// By default, this widget owns its ``OwnIDCreatePasskeyWidgetViewModel``. Inject a view model when your app
/// needs to keep completion state across custom view lifecycles or reuse the view model in custom widget UI.
///
/// The widget uses explicit ``widgetStrings`` immediately when they are provided. Otherwise it starts from
/// ``BoostWidgetStrings/default`` and automatically uses localized widget strings for ``instanceName`` when they
/// become available.
///
/// Pass an explicit ``OwnIDTheme`` with `theme:` when this widget should use a stable theme value. When omitted,
/// the widget follows the current ``EnvironmentValues/ownIDTheme`` or captures the current SwiftUI color scheme and
/// primary accent color. Parent `.tint(_:)` modifiers are not a supported way to configure OwnID theme tokens.
public struct OwnIDCreatePasskeyWidget<IconButton: View, OrText: View, Checkmark: View>: View {
    @State private var ownedViewModel: OwnIDCreatePasskeyWidgetViewModel
    @State private var uiState: OwnIDCreatePasskeyWidgetViewModel.UIState
    @State private var resolvedWidgetStrings: BoostWidgetStrings? = nil

    private let instanceName: InstanceName
    private let loginID: String?
    private let showSpinner: Bool
    private let position: OwnIDBoostButtonPosition
    private let theme: OwnIDTheme?
    private let providedViewModel: OwnIDCreatePasskeyWidgetViewModel?
    private let widgetStrings: BoostWidgetStrings?
    @LatestValue private var onNewPasskey: (BoostFlowCreatePasskeyResponse) -> Void
    @LatestValue private var onLogin: (BoostFlowLoginResponse) -> Void
    @LatestValue private var onReset: () -> Void
    @LatestValue private var onCancel: ((Reason) -> Void)?
    @LatestValue private var onError: ((BoostCreatePasskeyFlowFailure) -> Void)?
    private let iconButton: (_ isBusy: Bool, _ isEnabled: Bool, _ action: @escaping () -> Void, _ accessibilityLabel: String) -> IconButton
    private let orText: (String) -> OrText
    private let checkmark: () -> Checkmark

    private var effectiveViewModel: OwnIDCreatePasskeyWidgetViewModel {
        providedViewModel ?? ownedViewModel
    }

    private static func normalizeLoginID(_ loginID: String?) -> String? {
        guard let loginID else { return nil }
        let normalizedLoginID = loginID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedLoginID.isEmpty else { return nil }
        return normalizedLoginID
    }

    internal init(
        onLogin: @escaping (BoostFlowLoginResponse) -> Void,
        onNewPasskey: @escaping (BoostFlowCreatePasskeyResponse) -> Void,
        onReset: @escaping () -> Void,
        loginID: String?,
        onError: ((BoostCreatePasskeyFlowFailure) -> Void)?,
        onCancel: ((Reason) -> Void)?,
        showSpinner: Bool,
        position: OwnIDBoostButtonPosition = .start,
        theme: OwnIDTheme?,
        instanceName: InstanceName,
        viewModel: OwnIDCreatePasskeyWidgetViewModel?,
        widgetStrings: BoostWidgetStrings?,
        @ViewBuilder iconButton:
            @escaping (_ isBusy: Bool, _ isEnabled: Bool, _ action: @escaping () -> Void, _ accessibilityLabel: String) -> IconButton,
        @ViewBuilder orText: @escaping (String) -> OrText,
        @ViewBuilder checkmark: @escaping () -> Checkmark
    ) {
        self._onLogin = LatestValue(wrappedValue: onLogin)
        self._onNewPasskey = LatestValue(wrappedValue: onNewPasskey)
        self._onReset = LatestValue(wrappedValue: onReset)
        self.loginID = loginID
        self._onError = LatestValue(wrappedValue: onError)
        self._onCancel = LatestValue(wrappedValue: onCancel)
        self.showSpinner = showSpinner
        self.position = position
        self.theme = theme
        self.instanceName = instanceName
        self.providedViewModel = viewModel
        self.widgetStrings = widgetStrings
        self.iconButton = iconButton
        self.orText = orText
        self.checkmark = checkmark

        self._ownedViewModel = State(initialValue: OwnIDCreatePasskeyWidgetViewModel(instanceName: instanceName))
        self._uiState = State(initialValue: OwnIDCreatePasskeyWidgetViewModel.UIState())
    }

    public var body: some View {
        let viewModel = effectiveViewModel
        let normalizedLoginID = Self.normalizeLoginID(loginID)
        let resolvedStrings = widgetStrings ?? resolvedWidgetStrings ?? .default

        OwnIDBoostButton(
            onClick: { viewModel.startFlow(loginID: normalizedLoginID) },
            isBusy: uiState.isRunning,
            instanceName: instanceName,
            position: position,
            finished: uiState.showCheckmark,
            showSpinner: showSpinner,
            theme: theme,
            widgetStrings: resolvedStrings,
        )
        .iconButton(iconButton)
        .orText(orText)
        .checkmark(checkmark)
        .taskCompat(id: "OwnIDCreatePasskeyWidget.loginID.\(ObjectIdentifier(viewModel).hashValue).\(normalizedLoginID ?? "nil")") {
            viewModel.onLoginIDChanged(normalizedLoginID)
        }
        .taskCompat(id: "OwnIDCreatePasskeyWidget.state.\(ObjectIdentifier(viewModel).hashValue)") {
            for await state in viewModel.uiStateStream {
                if Task.isCancelled { break }
                uiState = state
            }
        }
        .taskCompat(id: "OwnIDCreatePasskeyWidget.effects.\(ObjectIdentifier(viewModel).hashValue)") {
            for await effect in viewModel.uiEffects {
                if Task.isCancelled { break }
                switch effect {
                case .resetRequested: $onReset.value()
                case .login(let response): $onLogin.value(response)
                case .createPasskey(let response): $onNewPasskey.value(response)
                case .error(let error): $onError.value?(error)
                case .canceled(let reason): $onCancel.value?(reason)
                }
            }
        }
        .boostWidgetStrings(
            instanceName: instanceName,
            widgetStrings: widgetStrings,
            resolvedWidgetStrings: $resolvedWidgetStrings
        )
    }
}

extension OwnIDCreatePasskeyWidget
where IconButton == OwnIDIconButtonView<RoundedRectangle>, OrText == Text, Checkmark == OwnIDCheckmarkView {
    /// Creates a Boost create-passkey widget using the default OwnID components.
    ///
    /// - Parameters:
    ///   - onLogin: Called when the flow completes by logging the user in instead of creating a new passkey.
    ///   - onNewPasskey: Called when the flow creates a new passkey, including re-emission from the widget view model
    ///     while it is still alive.
    ///   - onReset: Called when previously completed create-passkey UI should be cleared for the current login ID. The
    ///     app should clear any screen state that was derived from the previous create-passkey callback.
    ///   - loginID: Optional raw login ID to prefill. Empty/blank values are ignored.
    ///   - onError: Called with ``BoostCreatePasskeyFlowFailure`` when the flow fails or cannot be started. Branch on the
    ///     concrete failure type to choose the screen's next step.
    ///   - onCancel: Called when the flow is canceled before success.
    ///   - showSpinner: Whether to show a spinner while the flow is running. Defaults to `true`; the widget still
    ///     prevents another tap while busy when this is `false`.
    ///   - position: Whether the OwnID Boost button appears before or after the "or" separator. Use
    ///     ``OwnIDBoostButtonPosition/end`` when you place the widget after the app's password field. Defaults to
    ///     ``OwnIDBoostButtonPosition/start``.
    ///   - theme: Optional OwnID theme for this widget. When `nil`, the widget uses the current OwnID theme.
    ///   - instanceName: Instance used for default flow provisioning and default widget-string resolution.
    ///   - viewModel: Optional externally owned widget view model. By default the widget creates its own view model
    ///     for `instanceName`. Provide one when the screen should control the widget lifetime.
    ///   - widgetStrings: Explicit strings for this widget. When provided, the widget renders them from the first
    ///     frame. Otherwise the widget starts from ``BoostWidgetStrings/default`` and then uses localized widget
    ///     strings for `instanceName` when they become available.
    public init(
        onLogin: @escaping (BoostFlowLoginResponse) -> Void,
        onNewPasskey: @escaping (BoostFlowCreatePasskeyResponse) -> Void,
        onReset: @escaping () -> Void,
        loginID: String? = nil,
        onError: ((BoostCreatePasskeyFlowFailure) -> Void)? = nil,
        onCancel: ((Reason) -> Void)? = nil,
        showSpinner: Bool = true,
        position: OwnIDBoostButtonPosition = .start,
        theme: OwnIDTheme? = nil,
        instanceName: InstanceName = .default,
        viewModel: OwnIDCreatePasskeyWidgetViewModel? = nil,
        widgetStrings: BoostWidgetStrings? = nil
    ) {
        self.init(
            onLogin: onLogin,
            onNewPasskey: onNewPasskey,
            onReset: onReset,
            loginID: loginID,
            onError: onError,
            onCancel: onCancel,
            showSpinner: showSpinner,
            position: position,
            theme: theme,
            instanceName: instanceName,
            viewModel: viewModel,
            widgetStrings: widgetStrings,
            iconButton: { isBusy, isEnabled, action, accessibilityLabel in
                OwnIDIconButtonView(
                    isBusy: isBusy,
                    accessibilityLabel: accessibilityLabel,
                    isEnabled: isEnabled,
                    action: action
                )
            },
            orText: { Text($0) },
            checkmark: { OwnIDCheckmarkView() }
        )
    }
}

extension OwnIDCreatePasskeyWidget {
    /// Returns a copy that uses custom "or" separator content.
    ///
    /// The closure receives the resolved localized text, usually "or". The returned view keeps the same flow,
    /// callback, reset, and view-model ownership as the original widget.
    public func orText<CustomOrText: View>(
        @ViewBuilder _ customOrText: @escaping (String) -> CustomOrText
    ) -> OwnIDCreatePasskeyWidget<IconButton, CustomOrText, Checkmark> {
        .init(
            onLogin: onLogin,
            onNewPasskey: onNewPasskey,
            onReset: onReset,
            loginID: loginID,
            onError: onError,
            onCancel: onCancel,
            showSpinner: showSpinner,
            position: position,
            theme: theme,
            instanceName: instanceName,
            viewModel: providedViewModel,
            widgetStrings: widgetStrings,
            iconButton: iconButton,
            orText: customOrText,
            checkmark: checkmark
        )
    }

    /// Returns a copy that uses a custom icon-button view.
    ///
    /// The closure receives the busy state, enabled state, tap action, and resolved accessibility label. Custom
    /// content should invoke the action from its primary user interaction and apply the label to the accessible control.
    public func iconButton<CustomIconButton: View>(
        @ViewBuilder _ customIconButton:
            @escaping (_ isBusy: Bool, _ isEnabled: Bool, _ action: @escaping () -> Void, _ accessibilityLabel: String) -> CustomIconButton
    ) -> OwnIDCreatePasskeyWidget<CustomIconButton, OrText, Checkmark> {
        .init(
            onLogin: onLogin,
            onNewPasskey: onNewPasskey,
            onReset: onReset,
            loginID: loginID,
            onError: onError,
            onCancel: onCancel,
            showSpinner: showSpinner,
            position: position,
            theme: theme,
            instanceName: instanceName,
            viewModel: providedViewModel,
            widgetStrings: widgetStrings,
            iconButton: customIconButton,
            orText: orText,
            checkmark: checkmark
        )
    }

    /// Returns a copy that uses a custom completion-checkmark view.
    ///
    /// The checkmark is presentation-only. Reset and create-passkey callbacks remain owned by the widget view model and
    /// the surrounding screen.
    public func checkmark<CustomCheckmark: View>(
        @ViewBuilder _ customCheckmark: @escaping () -> CustomCheckmark
    ) -> OwnIDCreatePasskeyWidget<IconButton, OrText, CustomCheckmark> {
        .init(
            onLogin: onLogin,
            onNewPasskey: onNewPasskey,
            onReset: onReset,
            loginID: loginID,
            onError: onError,
            onCancel: onCancel,
            showSpinner: showSpinner,
            position: position,
            theme: theme,
            instanceName: instanceName,
            viewModel: providedViewModel,
            widgetStrings: widgetStrings,
            iconButton: iconButton,
            orText: orText,
            checkmark: customCheckmark
        )
    }
}
