// Theme.swift: shared design tokens and the single availability gate for system surfaces.
#if canImport(SwiftUI)
import SwiftUI

enum Theme {
    // MARK: Colors

    /// Near-black base used behind every screen.
    static let background = Color(white: 0.05)
    /// Default surface for cards, fields and chips.
    static let surface = Color(white: 0.11)
    /// A surface one step above `surface`.
    static let elevated = Color(white: 0.16)
    /// Low-contrast separator lines and progress tracks.
    static let separator = Color.white.opacity(0.12)
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.66)
    static let tertiaryText = Color.white.opacity(0.42)
    /// The app's single accent is white; artwork supplies the only other color.
    static let accent = Color.white
    static let destructive = Color.red

    // MARK: Spacing

    static let spacing: CGFloat = 16
    static let tight: CGFloat = 8
    static let sectionSpacing: CGFloat = 24
    static let screenPadding: CGFloat = 20
    static let rowSpacing: CGFloat = 12

    // MARK: Radii

    static let corner: CGFloat = 16
    static let cardRadius: CGFloat = 12
    static let artworkRadius: CGFloat = 4
    static let albumRadius: CGFloat = 8
    static let tileRadius: CGFloat = 6
    static let chipRadius: CGFloat = 14

    // MARK: Sizes

    static let controlSize: CGFloat = 44
    static let miniArtworkSize: CGFloat = 42
    static let miniPlayerHeight: CGFloat = 64

    // MARK: Type

    static let screenTitle = Font.largeTitle.bold()
    static let sectionTitle = Font.title3.bold()
    static let rowTitle = Font.subheadline.weight(.semibold)
    static let rowSubtitle = Font.caption
    static let caption = Font.caption
    static let time = Font.caption.monospacedDigit()
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

    /// Sits above the tab bar on every iOS version.
    @ViewBuilder
    func nowPlayingBarInset<Content: View>(
        isPresented: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            if isPresented {
                content()
                    .background(.bar)
                    .overlay(alignment: .top) { Divider() }
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
