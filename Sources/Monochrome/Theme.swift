// Theme.swift: shared design tokens and the single availability gate for system surfaces.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI
import UIKit

enum Theme {
    // MARK: Colors

    /// Near-black in dark appearance, off-white in light appearance.
    static let background = adaptive(
        light: UIColor(white: 0.98, alpha: 1),
        dark: UIColor(white: 0.02, alpha: 1)
    )
    /// Default surface for cards, fields and chips.
    static let surface = adaptive(
        light: UIColor(white: 0.94, alpha: 1),
        dark: UIColor(white: 0.07, alpha: 1)
    )
    /// A surface one step above `surface`.
    static let elevated = adaptive(
        light: .white,
        dark: UIColor(white: 0.12, alpha: 1)
    )
    /// Thin rules and card outlines.
    static let border = adaptive(
        light: UIColor.black.withAlphaComponent(0.12),
        dark: UIColor.white.withAlphaComponent(0.14)
    )
    /// Quiet separators and idle progress tracks.
    static let separator = adaptive(
        light: UIColor.black.withAlphaComponent(0.09),
        dark: UIColor.white.withAlphaComponent(0.10)
    )

    static let primaryText = adaptive(light: .black, dark: .white)
    static let secondaryText = adaptive(
        light: UIColor.black.withAlphaComponent(0.60),
        dark: UIColor.white.withAlphaComponent(0.62)
    )
    static let tertiaryText = adaptive(
        light: UIColor.black.withAlphaComponent(0.42),
        dark: UIColor.white.withAlphaComponent(0.38)
    )

    /// The one meaningful accent: selection, progress and active playback state.
    static let accent = adaptive(
        light: UIColor(red: 0.69, green: 0.00, blue: 0.06, alpha: 1),
        dark: UIColor(red: 0.88, green: 0.10, blue: 0.14, alpha: 1)
    )
    static let onAccent = Color.white
    static let destructive = accent

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

    // MARK: Type

    static let screenTitle = Font.system(.largeTitle, design: .default, weight: .bold)
    static let heroTitle = Font.system(.title, design: .default, weight: .bold)
    static let sectionTitle = Font.system(.title3, design: .default, weight: .semibold)
    static let rowTitle = Font.system(.subheadline, design: .default, weight: .semibold)
    static let rowSubtitle = Font.system(.caption, design: .default)
    static let caption = Font.system(.caption, design: .default)
    static let technical = Font.system(.caption, design: .monospaced, weight: .medium)
    static let micro = Font.system(.caption2, design: .monospaced, weight: .semibold)
    static let time = Font.system(.caption, design: .monospaced, weight: .medium)

    // MARK: Motion

    static let quick = Animation.easeOut(duration: 0.18)
    static let standard = Animation.easeInOut(duration: 0.28)

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
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
