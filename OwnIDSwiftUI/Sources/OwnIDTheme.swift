import Foundation
@_spi(OwnIDInternal) import OwnIDCore
import SwiftUI

/// A theme value applied to OwnID content.
///
/// An OwnID theme carries semantic ``OwnIDColors`` used by SDK controls, fields, and container surfaces. Pass a theme
/// directly to widgets and ``OwnIDOperationView`` when that call site should use stable colors. Use
/// ``View/ownIDTheme(instanceName:customize:)`` when SDK-presented OwnID UI should reuse colors captured from your
/// app hierarchy.
public struct OwnIDTheme: Sendable, Equatable, Hashable {
    /// Semantic color tokens used by OwnID controls, fields, and container surfaces.
    public var colors: OwnIDColors

    /// Creates a theme from semantic OwnID color tokens.
    public init(colors: OwnIDColors) {
        self.colors = colors
    }

    /// Captures an OwnID theme from the current SwiftUI appearance.
    ///
    /// Use this when OwnID UI should follow the supplied SwiftUI color scheme and primary accent color while keeping
    /// SDK defaults for tokens that do not map directly to SwiftUI semantics. The captured palette maps SwiftUI and
    /// UIKit colors to OwnID roles: `.accentColor` for primary, system red for error, system background for surface,
    /// `.primary` and `.secondary` for content, secondary system background for fields and icon buttons, and separator
    /// for icon-button borders.
    ///
    /// This does not capture arbitrary parent view modifiers such as `.tint(_:)`; use
    /// ``capture(colorScheme:primary:onPrimary:)`` when OwnID controls should use a specific primary color.
    public static func capture(colorScheme: ColorScheme) -> OwnIDTheme {
        OwnIDTheme(colors: OwnIDColors.capture(colorScheme: colorScheme))
    }

    /// Captures an OwnID theme and applies a custom primary color pair.
    ///
    /// Use this when OwnID controls should use your app or brand color while the rest of the palette follows the
    /// supplied SwiftUI color scheme. Pass the readable foreground for that color with `onPrimary`, for example
    /// `.white` on a dark primary color.
    public static func capture(colorScheme: ColorScheme, primary: Color, onPrimary: Color) -> OwnIDTheme {
        OwnIDTheme(colors: OwnIDColors.capture(colorScheme: colorScheme, primary: primary, onPrimary: onPrimary))
    }

    internal static func sdkDefault(for colorScheme: ColorScheme) -> OwnIDTheme {
        OwnIDTheme(colors: OwnIDColors.sdkDefault(for: colorScheme))
    }
}

internal struct OwnIDThemeKey: EnvironmentKey {
    internal static let defaultValue: OwnIDTheme? = nil
}

extension EnvironmentValues {
    /// The OwnID theme resolved for the current SwiftUI hierarchy.
    ///
    /// Custom OwnID views can read this value to stay aligned with surrounding OwnID styling. The default value is
    /// `nil`; treat `nil` as no local OwnID theme and fall back to ``OwnIDTheme/capture(colorScheme:)`` for
    /// app-owned SwiftUI content.
    public var ownIDTheme: OwnIDTheme? {
        get { self[OwnIDThemeKey.self] }
        set { self[OwnIDThemeKey.self] = newValue }
    }
}

internal final class OwnIDThemeStore: ObservableObject, @unchecked Sendable {
    @Published internal private(set) var theme: OwnIDTheme? = nil

    @MainActor
    internal func set(_ theme: OwnIDTheme) {
        guard self.theme != theme else { return }
        self.theme = theme
    }
}

internal struct OwnIDThemeBridge: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    private let instanceName: InstanceName
    private let customize: (ColorScheme, inout OwnIDTheme) -> Void

    internal init(
        instanceName: InstanceName,
        customize: @escaping (ColorScheme, inout OwnIDTheme) -> Void
    ) {
        self.instanceName = instanceName
        self.customize = customize
    }

    private var resolvedTheme: OwnIDTheme {
        var theme = OwnIDTheme.capture(colorScheme: colorScheme)
        customize(colorScheme, &theme)
        return theme
    }

    internal func body(content: Content) -> some View {
        content
            .background(ThemeStoreBindingView(instanceName: instanceName, theme: resolvedTheme))
    }
}

private struct ThemeStoreBindingView: View {
    let instanceName: InstanceName
    let theme: OwnIDTheme

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .taskCompat(id: ThemeBindingTaskID(instanceName: instanceName, theme: theme)) {
                for await instanceContainer in OwnID.getInstanceContainerStream(instanceName) {
                    if Task.isCancelled { break }
                    guard let instanceContainer else { continue }
                    instanceContainer.getOrNil(type: OwnIDThemeStore.self)?.set(theme)
                }
            }
    }
}

private struct ThemeBindingTaskID: Hashable {
    let instanceName: InstanceName
    let theme: OwnIDTheme
}

extension View {
    /// Captures the current SwiftUI appearance and publishes it for SDK-presented OwnID UI.
    ///
    /// Apply this inside your app's themed SwiftUI hierarchy when SDK-presented OwnID UI for the same `instanceName`
    /// should reuse that styling later. The modifier reads the current `colorScheme` from the SwiftUI environment and
    /// publishes a new theme when that environment value changes.
    ///
    /// Use `customize` to align OwnID colors with your app theme:
    ///
    /// ```swift
    /// rootView.ownIDTheme { colorScheme, theme in
    ///     let palette = AppPalette.ownIDPalette(for: colorScheme)
    ///     theme.colors.primary = palette.primary
    ///     theme.colors.onPrimary = palette.onPrimary
    ///     theme.colors.surface = palette.surface
    ///     theme.colors.onSurface = palette.text
    ///     theme.colors.onSurfaceVariant = palette.secondaryText
    ///     theme.colors.fieldBackground = palette.fieldBackground
    /// }
    /// ```
    ///
    /// This modifier publishes the resolved theme for OwnID UI that the SDK presents itself. Until this modifier
    /// publishes a theme, SDK-presented UI uses the SDK light or dark default palette for the active color scheme. The
    /// last published theme for `instanceName` stays active until another application of this modifier publishes a
    /// replacement theme or the OwnID instance is recreated. It does not change the local SwiftUI environment for
    /// app-owned OwnID views. For ``OwnIDLoginWidget``, ``OwnIDCreatePasskeyWidget``, or ``OwnIDOperationView``, pass
    /// an explicit `theme:` when a specific call site should use a stable theme value.
    ///
    /// - Parameters:
    ///   - instanceName: OwnID instance that should receive the published theme for SDK-presented UI. Defaults to
    ///     `.default`.
    ///   - customize: Optional overrides applied after the SDK captures the current SwiftUI appearance.
    public func ownIDTheme(
        instanceName: InstanceName = .default,
        customize: @escaping (ColorScheme, inout OwnIDTheme) -> Void = { _, _ in }
    ) -> some View {
        modifier(OwnIDThemeBridge(instanceName: instanceName, customize: customize))
    }
}
