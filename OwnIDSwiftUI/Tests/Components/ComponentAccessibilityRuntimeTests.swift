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
        .iconButton { isBusy, isEnabled, action, accessibilityLabel in
            RecordingBoostButtonSlot(
                isBusy: isBusy,
                isEnabled: isEnabled,
                action: action,
                accessibilityLabel: accessibilityLabel,
                probe: probe
            )
        }

        let host = SwiftUIRuntimeHost(rootView: button.frame(width: 180, height: 64), size: CGSize(width: 220, height: 120))
        defer { host.close() }

        #expect(probe.latest == ButtonSlotSnapshot.busy(accessibilityLabel: "Skip password"))
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
        .iconButton { isBusy, isEnabled, action, accessibilityLabel in
            RecordingBoostButtonSlot(
                isBusy: isBusy,
                isEnabled: isEnabled,
                action: action,
                accessibilityLabel: accessibilityLabel,
                probe: probe
            )
        }

        let host = SwiftUIRuntimeHost(rootView: button.frame(width: 180, height: 64), size: CGSize(width: 220, height: 120))
        defer { host.close() }

        #expect(probe.latest == ButtonSlotSnapshot.ready(accessibilityLabel: "Skip password"))
    }

}

@MainActor
private final class BoostButtonSlotProbe {
    private(set) var latest: ButtonSlotSnapshot?

    func record(_ state: ButtonSlotSnapshot) {
        latest = state
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
            )
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
