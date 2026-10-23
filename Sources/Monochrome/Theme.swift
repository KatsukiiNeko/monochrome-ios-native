// Theme.swift: shared design tokens and the single availability gate for system surfaces.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI
import UIKit

enum Theme {
    // MARK: Colors

    /// Near-black in dark appearance, off-white in light appearance.
    static let background = adaptive(
        light: ThemePalette.light.background,
        dark: ThemePalette.dark.background
    )
    /// Default surface for cards, fields and chips.
    static let surface = adaptive(
        light: ThemePalette.light.surface,
        dark: ThemePalette.dark.surface
    )
    /// A surface one step above `surface`.
    static let elevated = adaptive(
        light: ThemePalette.light.elevated,
        dark: ThemePalette.dark.elevated
    )
    /// Recessed control surface, used for fields and selected segments.
    static let sunken = adaptive(
        light: ThemePalette.light.sunken,
        dark: ThemePalette.dark.sunken
    )
    /// Low-intensity red wash for a selected control; never a page background.
    static let accentSurface = adaptive(
        light: ThemePalette.light.accentSurface,
        dark: ThemePalette.dark.accentSurface
    )
    /// Thin rules and card outlines.
    static let border = adaptive(
        light: ThemePalette.light.border,
        dark: ThemePalette.dark.border
    )
    /// Quiet separators and idle progress tracks.
    static let separator = adaptive(
        light: ThemePalette.light.separator,
        dark: ThemePalette.dark.separator
    )

    static let primaryText = adaptive(
        light: ThemePalette.light.primaryText,
        dark: ThemePalette.dark.primaryText
    )
    static let secondaryText = adaptive(
        light: ThemePalette.light.secondaryText,
        dark: ThemePalette.dark.secondaryText
    )
    static let tertiaryText = adaptive(
        light: ThemePalette.light.tertiaryText,
        dark: ThemePalette.dark.tertiaryText
    )

    /// The one meaningful accent: selection, progress and active playback state.
    static let accent = adaptive(
        light: ThemePalette.light.accent,
        dark: ThemePalette.dark.accent
    )
    static let onAccent = Color.white
    static let destructive = adaptive(
        light: ThemePalette.light.destructive,
        dark: ThemePalette.dark.destructive
    )

    /// High-contrast transport surface, independent of the red state accent.
    static let primaryAction = adaptive(light: .black, dark: .white)
    static let onPrimaryAction = adaptive(light: .white, dark: .black)

    /// The mini-player card keeps its dark artwork tint in both appearances.
    static let onTintPrimary = Color.white
    static let onTintSecondary = Color.white.opacity(0.70)
    static let onTintSeparator = Color.white.opacity(0.18)
    static let onTintAccent = Color(red: 0.98, green: 0.22, blue: 0.24)

    // MARK: Spacing

    static let sectionSpacing: CGFloat = 28
    static let screenPadding: CGFloat = 20
    static let rowSpacing: CGFloat = 12
    static let hairline: CGFloat = 1
    static let cardPadding: CGFloat = 14
    static let rowMinHeight: CGFloat = 52
    static let iconSize: CGFloat = 28

    // MARK: Radii

    static let corner: CGFloat = 12
    static let cardRadius: CGFloat = 10
    static let artworkRadius: CGFloat = 2
    static let albumRadius: CGFloat = 4
    static let tileRadius: CGFloat = 6
    static let chipRadius: CGFloat = 5

    // MARK: Sizes

    static let controlSize: CGFloat = 44
    static let miniArtworkSize: CGFloat = 42
    static let sectionMarker: CGFloat = 5
    static let markerHeight: CGFloat = 13

    // MARK: Type

    static let screenTitle = Font.system(.largeTitle, design: .default, weight: .bold)
    static let heroTitle = Font.system(.title, design: .default, weight: .bold)
    static let sectionTitle = Font.system(.title3, design: .default, weight: .semibold)
    static let shelfTitle = Font.system(.title2, design: .default, weight: .bold)
    static let rowTitle = Font.system(.subheadline, design: .default, weight: .semibold)
    static let listRowTitle = Font.system(.body, design: .default, weight: .medium)
    static let rowSubtitle = Font.system(.caption, design: .default)
    static let caption = Font.system(.caption, design: .default)
    static let technical = Font.system(.caption, design: .monospaced, weight: .medium)
    static let micro = Font.system(.caption2, design: .monospaced, weight: .semibold)
    static let time = Font.system(.caption, design: .monospaced, weight: .medium)
    static let value = Font.system(.subheadline, design: .monospaced, weight: .medium)

    // MARK: Motion

    static let quick = Animation.easeOut(duration: 0.18)
    static let standard = Animation.easeInOut(duration: 0.28)
    static let artwork = Animation.easeOut(duration: 0.32)

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    private static func adaptive(light: PaletteColor, dark: PaletteColor) -> Color {
        Color(uiColor: UIColor { traits in
            let color = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: color.red,
                green: color.green,
                blue: color.blue,
                alpha: color.alpha
            )
        })
    }
}

extension AppearanceMode {
    /// `nil` restores the system appearance.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

extension Color {
    init(_ tint: ArtworkTintColor) {
        self.init(.sRGB, red: tint.red, green: tint.green, blue: tint.blue, opacity: 1)
    }
}

extension View {
    /// iOS 26 glass buttons; bordered buttons on older systems. One gate for the whole app.
    @ViewBuilder
    func glassControlStyle() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }

    /// Material surface for floating controls; solid when transparency is reduced.
    func glassSurface(cornerRadius: CGFloat = Theme.corner) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius))
    }

    /// Sits above the tab bar on every iOS version. The content supplies its own card.
    @ViewBuilder
    func nowPlayingBarInset<Content: View>(
        isPresented: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            if isPresented {
                content()
            }
        }
    }
}

private struct GlassSurface: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content.background(
            reduceTransparency ? AnyShapeStyle(Theme.surface) : AnyShapeStyle(.thinMaterial),
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }
}
#endif
