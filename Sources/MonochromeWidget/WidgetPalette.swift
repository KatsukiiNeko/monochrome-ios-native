// WidgetPalette.swift: core RGB tokens mapped to SwiftUI colors.
#if canImport(WidgetKit)
import MonochromeCore
import SwiftUI

extension Color {
    init(_ color: PaletteColor) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
    }
}

enum WidgetTheme {
    // The widget always uses the app's dark palette, the same one as the player.
    static let palette = ThemePalette.dark
    static var background: Color { Color(palette.background) }
    static var surface: Color { Color(palette.surface) }
    static var elevated: Color { Color(palette.elevated) }
    static var sunken: Color { Color(palette.sunken) }
    static var accent: Color { Color(palette.accent) }
    static var accentSurface: Color { Color(palette.accentSurface) }
    static var border: Color { Color(palette.border) }
    static var primaryText: Color { Color(palette.primaryText) }
    static var secondaryText: Color { Color(palette.secondaryText) }
    static var tertiaryText: Color { Color(palette.tertiaryText) }
}
#endif
