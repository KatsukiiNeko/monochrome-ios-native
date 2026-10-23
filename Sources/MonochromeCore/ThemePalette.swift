// ThemePalette.swift: light and dark palettes plus WCAG contrast math.
import Foundation

/// Normalized RGBA, each channel in 0...1.
public struct PaletteColor: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static func gray(_ value: Double, alpha: Double = 1) -> PaletteColor {
        PaletteColor(red: value, green: value, blue: value, alpha: alpha)
    }

    /// Flattens this color over an opaque backdrop, returning an opaque color.
    public func composited(over backdrop: PaletteColor) -> PaletteColor {
        let opacity = min(max(alpha, 0), 1)
        let remainder = 1 - opacity
        return PaletteColor(
            red: red * opacity + backdrop.red * remainder,
            green: green * opacity + backdrop.green * remainder,
            blue: blue * opacity + backdrop.blue * remainder
        )
    }
}

public struct Palette: Equatable, Sendable {
    public var background: PaletteColor
    public var surface: PaletteColor
    public var elevated: PaletteColor
    public var sunken: PaletteColor
    public var accentSurface: PaletteColor
    public var border: PaletteColor
    public var separator: PaletteColor
    public var primaryText: PaletteColor
    public var secondaryText: PaletteColor
    public var tertiaryText: PaletteColor
    public var accent: PaletteColor
}

public enum ThemePalette {
    public static let light = Palette(
        background: .gray(0.98),
        surface: .gray(0.94),
        elevated: .gray(1.0),
        sunken: .gray(0.90),
        accentSurface: PaletteColor(red: 0.69, green: 0, blue: 0.06, alpha: 0.10),
        border: .gray(0, alpha: 0.12),
        separator: .gray(0, alpha: 0.09),
        primaryText: .gray(0.05),
        secondaryText: .gray(0.40),
        tertiaryText: .gray(0.55),
        accent: PaletteColor(red: 0.69, green: 0, blue: 0.06)
    )

    public static let dark = Palette(
        background: .gray(0.02),
        surface: .gray(0.07),
        elevated: .gray(0.12),
        sunken: .gray(0.045),
        accentSurface: PaletteColor(red: 0.88, green: 0.10, blue: 0.14, alpha: 0.18),
        border: .gray(1, alpha: 0.14),
        separator: .gray(1, alpha: 0.10),
        primaryText: .gray(0.98),
        secondaryText: .gray(0.72),
        tertiaryText: .gray(0.55),
        accent: PaletteColor(red: 0.88, green: 0.10, blue: 0.14)
    )

    /// WCAG contrast ratio. A translucent foreground is composited over the
    /// background first, so the background must itself be opaque.
    public static func contrastRatio(_ foreground: PaletteColor, _ background: PaletteColor) -> Double {
        let front = foreground.composited(over: background)
        let lighter = max(luminance(front), luminance(background))
        let darker = min(luminance(front), luminance(background))
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func luminance(_ color: PaletteColor) -> Double {
        func linear(_ value: Double) -> Double {
            let channel = min(max(value, 0), 1)
            return channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red)
            + 0.7152 * linear(color.green)
            + 0.0722 * linear(color.blue)
    }
}
