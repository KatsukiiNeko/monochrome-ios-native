// Theme.swift: shared spacing and the single availability gate for glass surfaces and controls.
#if canImport(SwiftUI)
import SwiftUI

enum Theme {
    static let spacing: CGFloat = 16
    static let tight: CGFloat = 8
    static let corner: CGFloat = 16
    static let artworkRadius: CGFloat = 10
    static let screenPadding: CGFloat = 20
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

    /// Sits above the tab bar on every iOS version. Applied to each tab's root, which also
    /// keeps it on pushed screens and lets scroll views inset their last row automatically.
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
            reduceTransparency ? AnyShapeStyle(Color(white: 0.12)) : AnyShapeStyle(.thinMaterial),
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }
}
#endif
