import Foundation
import SwiftUI

internal struct UserActionThrottler {
    private let throttleDelayNanoseconds: UInt64
    private let now: () -> UInt64
    private var lastActionTime: UInt64?

    internal init(
        throttleDelay: TimeInterval = 0.3,
        now: @escaping () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
    ) {
        self.throttleDelayNanoseconds = UInt64((throttleDelay * 1_000_000_000).rounded())
        self.now = now
    }

    internal mutating func processAction(_ action: () -> Void) {
        let currentTime = now()
        if lastActionTime.map({ currentTime - $0 >= throttleDelayNanoseconds }) ?? true {
            lastActionTime = currentTime
            action()
        }
    }
}

/// Internal text-only action button that follows the current OwnID theme.
///
/// The caller owns the enabled state and action. Disabled buttons do not invoke `action`; enabled taps ignore rapid
/// repeats. The visible text is also applied as the accessibility label.
internal struct OwnIDTextButtonView: View {
    @Environment(\.ownIDTheme) private var ownIDTheme
    @Environment(\.colorScheme) private var colorScheme
    @State private var throttler = UserActionThrottler()

    private let text: String
    private let isEnabled: Bool
    private let action: () -> Void

    internal init(
        text: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.text = text
        self.isEnabled = isEnabled
        self.action = action
    }

    private var colors: OwnIDColors {
        (ownIDTheme ?? OwnIDTheme.capture(colorScheme: colorScheme)).colors
    }

    internal var body: some View {
        Button(action: { throttler.processAction { action() } }) {
            Text(text)
                .font(.system(.subheadline, design: .default).weight(.semibold))
                .foregroundColor(isEnabled ? colors.primary : colors.primary.opacity(0.38))
                .padding(.horizontal, 8)
                .frame(minWidth: 96, minHeight: 44)
        }
        .disabled(!isEnabled)
        .accessibilityLabelCompat(text)
    }
}

/// Internal primary action button that follows the current OwnID theme.
///
/// The caller owns the enabled state and action. Disabled buttons do not invoke `action`; enabled taps ignore rapid
/// repeats. The visible text is also applied as the accessibility label.
internal struct OwnIDButtonView: View {
    @Environment(\.ownIDTheme) private var ownIDTheme
    @Environment(\.colorScheme) private var colorScheme
    @State private var throttler = UserActionThrottler()

    private let text: String
    private let isEnabled: Bool
    private let action: () -> Void

    internal init(
        text: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.text = text
        self.isEnabled = isEnabled
        self.action = action
    }

    private var colors: OwnIDColors {
        (ownIDTheme ?? OwnIDTheme.capture(colorScheme: colorScheme)).colors
    }

    internal var body: some View {
        Button(action: { throttler.processAction { action() } }) {
            Text(text)
                .font(.system(.body, design: .default).weight(.medium))
                .foregroundColor(isEnabled ? colors.onPrimary : colors.onPrimary.opacity(0.38))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(minWidth: 120, minHeight: 44)
                .background(isEnabled ? colors.primary : colors.primary.opacity(0.12))
                .cornerRadius(6.0)
        }
        .disabled(!isEnabled)
        .accessibilityLabelCompat(text)
    }
}

internal struct ShakeViewModifier: GeometryEffect {
    internal var amount: CGFloat = 10
    internal var shakesPerUnit = 3
    internal var animatableData: CGFloat

    internal func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(
            CGAffineTransform(translationX: amount * sin(animatableData * .pi * CGFloat(shakesPerUnit)), y: 0)
        )
    }
}

extension View {
    internal func shake(animatableData: Int, isEnabled: Bool = true) -> some View {
        let shakeValue = resolvedShakeAnimatableData(animatableData, isEnabled: isEnabled)
        return
            self
            .modifier(ShakeViewModifier(animatableData: shakeValue))
            .animationCompat(isEnabled ? .default : nil, value: shakeValue)
    }
}

internal func resolvedShakeAnimatableData(_ animatableData: Int, isEnabled: Bool) -> CGFloat {
    isEnabled ? CGFloat(animatableData) : 0
}
