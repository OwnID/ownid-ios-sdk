import SwiftUI
import UIKit

/// Color configuration for ``OwnIDIconButtonView``.
///
/// The default values come from ``OwnIDColors`` through ``OwnIDIconButtonDefaults/colors(colors:)``.
public struct OwnIDIconButtonColors {
    internal let containerColor: Color
    internal let contentColor: Color
    internal let borderColor: Color
    internal let disabledContainerColor: Color
    internal let disabledContentColor: Color

    /// Creates a color set for the icon button.
    public init(
        containerColor: Color,
        contentColor: Color,
        borderColor: Color,
        disabledContainerColor: Color,
        disabledContentColor: Color
    ) {
        self.containerColor = containerColor
        self.contentColor = contentColor
        self.borderColor = borderColor
        self.disabledContainerColor = disabledContainerColor
        self.disabledContentColor = disabledContentColor
    }
}

/// Border configuration for ``OwnIDIconButtonView``.
public struct OwnIDIconButtonBorder {
    internal let color: Color
    internal let lineWidth: CGFloat

    /// Creates a border configuration.
    public init(color: Color, lineWidth: CGFloat = 1) {
        self.color = color
        self.lineWidth = lineWidth
    }
}

/// Default shape and color values for ``OwnIDIconButtonView``.
public enum OwnIDIconButtonDefaults {
    /// Default shape for the icon button.
    public static var shape: some InsettableShape {
        RoundedRectangle(cornerRadius: 6)
    }

    /// Returns default button colors derived from the provided OwnID theme colors.
    public static func colors(colors: OwnIDColors) -> OwnIDIconButtonColors {
        OwnIDIconButtonColors(
            containerColor: colors.iconButtonBackground,
            contentColor: colors.primary,
            borderColor: colors.iconButtonBorder,
            disabledContainerColor: colors.iconButtonBackgroundDisabled,
            disabledContentColor: colors.primary.opacity(0.38)
        )
    }
}

/// Displays the standard OwnID icon button.
///
/// The button shows `icon` when `isBusy` is false and ``OwnIDSpinnerView`` when `isBusy` is true. Busy state is
/// visual only; `isEnabled` controls whether the button accepts input. Enabled taps ignore rapid repeat
/// submissions.
///
/// `accessibilityLabel` is applied to the button. The icon and spinner are decorative within that button, so they
/// do not expose separate labels. The control keeps a square aspect ratio and should be placed in a container that
/// allows at least a 44 point touch target.
public struct OwnIDIconButtonView<ButtonShape: InsettableShape>: View {
    @Environment(\.ownIDTheme) private var ownIDTheme
    @Environment(\.colorScheme) private var colorScheme
    @State private var throttler = UserActionThrottler()

    private let isBusy: Bool
    private let isEnabled: Bool
    private let icon: Image
    private let accessibilityLabel: String
    private let action: () -> Void
    private let customColors: OwnIDIconButtonColors?
    private let shape: ButtonShape
    private let border: OwnIDIconButtonBorder?

    /// Creates an icon button.
    ///
    /// - Parameters:
    ///   - isBusy: Whether to show progress instead of `icon`.
    ///   - accessibilityLabel: Accessibility label for the button action.
    ///   - shape: The button shape.
    ///   - isEnabled: Whether the button accepts input. Defaults to `true`.
    ///   - icon: The icon to display when not busy. Defaults to the system `faceid` symbol.
    ///   - colors: Optional custom colors. When `nil`, defaults are derived from the current OwnID theme.
    ///   - border: Optional border override. When `nil`, the default border uses the resolved colors and disabled
    ///     state.
    ///   - action: Action invoked when the enabled button is activated.
    public init(
        isBusy: Bool,
        accessibilityLabel: String,
        shape: ButtonShape,
        isEnabled: Bool = true,
        icon: Image = Image(systemName: "faceid"),
        colors: OwnIDIconButtonColors? = nil,
        border: OwnIDIconButtonBorder? = nil,
        action: @escaping () -> Void
    ) {
        self.isBusy = isBusy
        self.isEnabled = isEnabled
        self.icon = icon
        self.accessibilityLabel = accessibilityLabel
        self.customColors = colors
        self.shape = shape
        self.border = border
        self.action = action
    }

    private var resolvedColors: OwnIDIconButtonColors {
        customColors ?? OwnIDIconButtonDefaults.colors(colors: (ownIDTheme ?? OwnIDTheme.capture(colorScheme: colorScheme)).colors)
    }

    private var resolvedBorder: OwnIDIconButtonBorder {
        border ?? OwnIDIconButtonBorder(color: resolvedColors.borderColor)
    }

    public var body: some View {
        Button(action: { throttler.processAction { action() } }) {
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)

                ZStack {
                    if isBusy {
                        OwnIDSpinnerView()
                            .frame(width: side * 0.55, height: side * 0.55)
                            .transition(.opacity.combined(with: .scale))
                    } else {
                        iconContent(side: side * 0.72)
                    }
                }
                .frame(width: side, height: side)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
            .animationCompat(.default, value: isBusy)
            .aspectRatio(1, contentMode: .fit)
            .foregroundColor(isEnabled ? resolvedColors.contentColor : resolvedColors.disabledContentColor)
            .background(
                shape
                    .fill(isEnabled ? resolvedColors.containerColor : resolvedColors.disabledContainerColor)
                    .overlay(
                        shape.strokeBorder(
                            isEnabled || isBusy ? resolvedBorder.color : resolvedBorder.color.opacity(0.12),
                            lineWidth: resolvedBorder.lineWidth
                        )
                    )
            )
        }
        .disabled(!isEnabled)
        .accessibilityLabelCompat(Text(accessibilityLabel))
    }

    @ViewBuilder
    private func iconContent(side: CGFloat) -> some View {
        Group {
            if #available(iOS 14, *) {
                icon
                    .resizable()
                    .scaledToFit()
            } else {
                faceIDIcon(side: side)
                    .renderingMode(.template)
            }
        }
        .frame(width: side, height: side)
        .transition(.opacity.combined(with: .scale))
    }

    private func faceIDIcon(side: CGFloat) -> Image {
        let configuration = UIImage.SymbolConfiguration(pointSize: max(side * 0.88, 1), weight: .light, scale: .default)
        guard let image = UIImage(systemName: "faceid", withConfiguration: configuration)?.withRenderingMode(.alwaysTemplate) else {
            return Image(systemName: "faceid")
        }
        return Image(uiImage: image)
    }
}

extension OwnIDIconButtonView where ButtonShape == RoundedRectangle {
    /// Creates an icon button that uses the default OwnID rounded-rectangle shape.
    ///
    /// - Parameters:
    ///   - isBusy: Whether to show progress instead of `icon`.
    ///   - accessibilityLabel: Accessibility label for the button action.
    ///   - isEnabled: Whether the button accepts input. Defaults to `true`.
    ///   - icon: The icon to display when not busy. Defaults to the system `faceid` symbol.
    ///   - colors: Optional custom colors. When `nil`, defaults are derived from the current OwnID theme.
    ///   - border: Optional border override. When `nil`, the default border uses the resolved colors and disabled
    ///     state.
    ///   - action: Action invoked when the enabled button is activated.
    public init(
        isBusy: Bool,
        accessibilityLabel: String,
        isEnabled: Bool = true,
        icon: Image = Image(systemName: "faceid"),
        colors: OwnIDIconButtonColors? = nil,
        border: OwnIDIconButtonBorder? = nil,
        action: @escaping () -> Void
    ) {
        self.init(
            isBusy: isBusy,
            accessibilityLabel: accessibilityLabel,
            shape: RoundedRectangle(cornerRadius: 6),
            isEnabled: isEnabled,
            icon: icon,
            colors: colors,
            border: border,
            action: action
        )
    }
}
