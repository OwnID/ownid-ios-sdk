import SwiftUI
import Testing
import UIKit

@_spi(OwnIDInternal) @testable import OwnIDCore
@_spi(OwnIDInternal) @testable import OwnIDSwiftUI

// Covers: UI-PRESENT-150
@MainActor
@Suite(.serialized)
struct ComponentAccessibilityRuntimeTests {

    @Test func `Boost button forwards busy disabled and accessibility label state to icon slot`() {
        let probe = BoostButtonSlotProbe()
        let button = OwnIDBoostButton(
            onClick: {},
            isBusy: true,
            instanceName: InstanceName(value: "component-accessibility"),
            enabled: nil,
            finished: false,
            showSpinner: true,
            widgetStrings: BoostWidgetStrings(skipPassword: "Skip password", or: "or")
        )
        .iconButton { isBusy, isEnabled, action, accessibilityLabel, icon in
            RecordingBoostButtonSlot(
                isBusy: isBusy,
                isEnabled: isEnabled,
                action: action,
                accessibilityLabel: accessibilityLabel,
                icon: icon,
                probe: probe
            )
        }

        let host = SwiftUIRuntimeHost(rootView: button.frame(width: 180, height: 64), size: CGSize(width: 220, height: 120))
        defer { host.close() }

        #expect(probe.latest == ButtonSlotSnapshot.busy(accessibilityLabel: "Skip password"))
        #expect(probe.latestIcon == Image(systemName: "faceid"))
    }

    @Test func `Boost button suppresses progress forwarding when spinner is disabled`() {
        let probe = BoostButtonSlotProbe()
        let button = OwnIDBoostButton(
            onClick: {},
            isBusy: true,
            instanceName: InstanceName(value: "component-accessibility"),
            enabled: true,
            finished: false,
            showSpinner: false,
            widgetStrings: BoostWidgetStrings(skipPassword: "Skip password", or: "or")
        )
        .iconButton { isBusy, isEnabled, action, accessibilityLabel, icon in
            RecordingBoostButtonSlot(
                isBusy: isBusy,
                isEnabled: isEnabled,
                action: action,
                accessibilityLabel: accessibilityLabel,
                icon: icon,
                probe: probe
            )
        }

        let host = SwiftUIRuntimeHost(rootView: button.frame(width: 180, height: 64), size: CGSize(width: 220, height: 120))
        defer { host.close() }

        #expect(probe.latest == ButtonSlotSnapshot.ready(accessibilityLabel: "Skip password"))
        #expect(probe.latestIcon == Image(systemName: "faceid"))
    }

    @Test func `Full custom Boost constructor forwards the icon and current action through copy modifiers`() throws {
        let probe = BoostButtonSlotProbe()
        var clicks = 0
        let button = OwnIDBoostButton(
            onClick: { clicks += 1 }, isBusy: false, instanceName: InstanceName(value: "custom-constructor-no-instance"),
            finished: false, showSpinner: false,
            widgetStrings: BoostWidgetStrings(skipPassword: "Custom label", or: "or"),
            iconButton: { busy, enabled, action, label, icon in
                RecordingBoostButtonSlot(
                    isBusy: busy, isEnabled: enabled, action: action, accessibilityLabel: label, icon: icon, probe: probe
                )
            }, orText: { Text($0) }, checkmark: { EmptyView() }
        ).orText { Text($0) }.checkmark { EmptyView() }
        let host = SwiftUIRuntimeHost(rootView: button, size: CGSize(width: 220, height: 120))
        defer { host.close() }
        #expect(probe.latest == .ready(accessibilityLabel: "Custom label"))
        #expect(probe.latestIcon == Image(systemName: "faceid"))
        let action = try #require(probe.latestAction)
        action()
        #expect(clicks == 1)
    }
}

@MainActor
private final class BoostButtonSlotProbe {
    private(set) var latest: ButtonSlotSnapshot?
    private(set) var latestIcon: Image?
    private(set) var latestAction: (() -> Void)?

    func record(_ state: ButtonSlotSnapshot, icon: Image, action: @escaping () -> Void) {
        latest = state
        latestIcon = icon
        latestAction = action
    }
}

private struct RecordingBoostButtonSlot: View {
    private let isBusy: Bool
    private let isEnabled: Bool
    private let action: () -> Void
    private let accessibilityLabel: String

    init(
        isBusy: Bool,
        isEnabled: Bool,
        action: @escaping () -> Void,
        accessibilityLabel: String,
        icon: Image,
        probe: BoostButtonSlotProbe
    ) {
        self.isBusy = isBusy
        self.isEnabled = isEnabled
        self.action = action
        self.accessibilityLabel = accessibilityLabel
        probe.record(
            ButtonSlotSnapshot(
                isBusy: isBusy,
                isEnabled: isEnabled,
                accessibilityLabel: accessibilityLabel
            ),
            icon: icon,
            action: action
        )
    }

    var body: some View {
        Button(action: action) {
            if isBusy {
                OwnIDSpinnerView()
                    .frame(width: 20, height: 20)
            } else {
                Text("Ready")
            }
        }
        .disabled(!isEnabled)
        .accessibilityLabelCompat(Text(accessibilityLabel))
    }
}
