import SwiftUI

/// Color configuration for ``OwnIDSpinnerView``.
///
/// The default values come from ``OwnIDColors`` through ``OwnIDSpinnerDefaults/colors(colors:)``.
public struct OwnIDSpinnerColors {
    internal let color: Color
    internal let trackColor: Color

    /// Creates a color set for the spinner.
    public init(color: Color, trackColor: Color) {
        self.color = color
        self.trackColor = trackColor
    }
}

/// Default color and stroke values for ``OwnIDSpinnerView``.
public enum OwnIDSpinnerDefaults {
    /// Default stroke style for the spinner.
    public static let style = StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)

    /// Returns default spinner colors derived from the provided OwnID theme colors.
    public static func colors(colors: OwnIDColors) -> OwnIDSpinnerColors {
        OwnIDSpinnerColors(color: colors.progress, trackColor: colors.progressTrack)
    }
}

/// Displays an OwnID activity indicator.
///
/// The spinner uses the current OwnID theme by default and respects Reduce Motion by presenting static progress.
/// It is usually placed inside a button or loading container that already owns the accessibility label. When used
/// as standalone status UI, provide the surrounding view label or accessibility value that should be announced.
/// Size is caller-controlled with layout modifiers.
public struct OwnIDSpinnerView: View {
    @Environment(\.ownIDTheme) private var ownIDTheme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    private let customColors: OwnIDSpinnerColors?
    private let strokeStyle: StrokeStyle

    @State private var circleLineLength: Double = 0.011
    @State private var circleRotation = 0.0

    private let animationDuration = 2.0
    private let maximumCircleLength: CGFloat = 1 / 3

    private var rotationAnimation: Animation {
        Animation
            .linear(duration: animationDuration)
            .repeatForever(autoreverses: false)
    }

    private var lineLengthAnimation: Animation {
        Animation
            .linear(duration: animationDuration)
            .repeatForever(autoreverses: true)
    }

    /// Creates a spinner view.
    ///
    /// - Parameters:
    ///   - colors: Optional custom colors. When `nil`, defaults are derived from the current OwnID theme.
    ///   - style: Stroke style to use. Defaults to ``OwnIDSpinnerDefaults/style``.
    public init(colors: OwnIDSpinnerColors? = nil, style: StrokeStyle = OwnIDSpinnerDefaults.style) {
        self.customColors = colors
        self.strokeStyle = style
    }

    public var body: some View {
        let themeColors = (ownIDTheme ?? OwnIDTheme.capture(colorScheme: colorScheme)).colors
        let colors = customColors ?? OwnIDSpinnerDefaults.colors(colors: themeColors)
        ZStack {
            Circle()
                .stroke(style: strokeStyle)
                .foregroundColor(colors.trackColor)

            Circle()
                .trim(from: 0, to: accessibilityReduceMotion ? maximumCircleLength : min(circleLineLength, maximumCircleLength))
                .stroke(style: strokeStyle)
                .foregroundColor(colors.color)
                .rotationEffect(.degrees(-90))
                .rotationEffect(.degrees(360 * circleRotation))
        }
        .onAppear {
            if accessibilityReduceMotion {
                circleRotation = 0
                circleLineLength = maximumCircleLength
            } else {
                circleRotation = 0
                circleLineLength = 0.011
                withAnimation(rotationAnimation) { circleRotation = 1 }
                withAnimation(lineLengthAnimation) { circleLineLength = 1 }
            }
        }
        .onChangeCompat(of: accessibilityReduceMotion) { reduceMotion in
            if reduceMotion {
                circleRotation = 0
                circleLineLength = maximumCircleLength
            } else {
                circleRotation = 0
                circleLineLength = 0.011
                withAnimation(rotationAnimation) { circleRotation = 1 }
                withAnimation(lineLengthAnimation) { circleLineLength = 1 }
            }
        }
    }
}

internal struct OwnIDLoadingPlaceholderView: View {
    internal var body: some View {
        OwnIDSpinnerView()
            .frame(width: 50, height: 50)
            .frame(maxWidth: .infinity)
            .frame(height: 200)
    }
}
