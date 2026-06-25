import SwiftUI
import Testing
import UIKit

@_spi(OwnIDInternal) @testable import OwnIDCore
@_spi(OwnIDInternal) @testable import OwnIDSwiftUI

@MainActor
@Suite(.serialized)
struct ComponentAccessibilityRuntimeTests {

    @Test func `Text and primary buttons expose labels and disabled traits`() throws {
        let host = SwiftUIRuntimeHost(
            rootView: VStack {
                OwnIDTextButtonView(text: "Cancel", isEnabled: true, action: {})
                OwnIDButtonView(text: "Continue", isEnabled: false, action: {})
            },
            size: CGSize(width: 220, height: 160)
        )
        defer { host.close() }

        let cancel = try #require(
            host.accessibilityElements().first { $0.accessibilityLabel == "Cancel" },
            "Expected mounted text button accessibility element"
        )
        let `continue` = try #require(
            host.accessibilityElements().first { $0.accessibilityLabel == "Continue" },
            "Expected mounted primary button accessibility element"
        )

        #expect(cancel.accessibilityTraits.contains(.button))
        #expect(cancel.accessibilityTraits.contains(.notEnabled) == false)
        #expect(`continue`.accessibilityTraits.contains(.button))
        #expect(`continue`.accessibilityTraits.contains(.notEnabled))
    }

    @Test func `Icon button exposes label disabled state and UIKit button traits`() throws {
        let button = OwnIDIconButtonView(
            isBusy: true,
            accessibilityLabel: "Continue with OwnID",
            isEnabled: false,
            action: {}
        )

        let host = SwiftUIRuntimeHost(rootView: button.frame(width: 64, height: 64), size: CGSize(width: 120, height: 120))
        defer { host.close() }

        let element = try #require(
            host.accessibilityElements().first { $0.accessibilityLabel == "Continue with OwnID" },
            "Expected mounted icon button accessibility element"
        )
        #expect(element.accessibilityTraits.contains(.button))
        #expect(element.accessibilityTraits.contains(.notEnabled))
    }

    @Test func `Checkmark badge is decorative by source contract`() {
        let checkmark = OwnIDCheckmarkView()

        let host = SwiftUIRuntimeHost(rootView: checkmark.frame(width: 32, height: 32), size: CGSize(width: 80, height: 80))
        defer { host.close() }

        #expect(host.accessibilityLabels().isEmpty)
    }

    @Test func `Spinner is decorative when caller supplies no status semantics`() {
        let spinner = OwnIDSpinnerView()

        let host = SwiftUIRuntimeHost(rootView: spinner.frame(width: 32, height: 32), size: CGSize(width: 80, height: 80))
        defer { host.close() }

        #expect(host.accessibilityLabels().isEmpty)
    }

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

    @available(iOS 15.0, *)
    @Test func `Default widget components preserve semantics under injectable Dynamic Type`() throws {
        let button = OwnIDBoostButton(
            onClick: {},
            isBusy: true,
            instanceName: InstanceName(value: "component-accessibility-settings"),
            enabled: nil,
            finished: true,
            showSpinner: true,
            widgetStrings: BoostWidgetStrings(skipPassword: "Skip password", or: "or")
        )
        .environment(\.dynamicTypeSize, .accessibility3)

        let host = SwiftUIRuntimeHost(rootView: button, size: CGSize(width: 220, height: 120))
        defer { host.close() }

        host.assertFittingSize(.compactWidget)
        let element = try #require(
            host.accessibilityElements().first { $0.accessibilityLabel == "Skip password" },
            "Expected mounted widget action accessibility element"
        )

        #expect(element.accessibilityTraits.contains(UIAccessibilityTraits.button))
        #expect(element.accessibilityTraits.contains(UIAccessibilityTraits.notEnabled))
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
