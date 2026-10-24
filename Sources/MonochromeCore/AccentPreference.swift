// AccentPreference.swift: persisted state accent choices and their contrast rules.
import Foundation

public enum AccentPreference: String, CaseIterable, Identifiable, Sendable {
    case mono
    case signal
    case amber
    case mint
    case blue
    case violet
    case artwork

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .mono: "Monochrome"
        case .signal: "Signal"
        case .amber: "Amber"
        case .mint: "Mint"
        case .blue: "Blue"
        case .violet: "Violet"
        case .artwork: "Match Artwork"
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .mono: "Monochrome accent"
        case .signal: "Signal accent"
        case .amber: "Amber accent"
        case .mint: "Mint accent"
        case .blue: "Blue accent"
        case .violet: "Violet accent"
        case .artwork: "Match artwork accent"
        }
    }
}

public struct AccentPalette: Equatable, Sendable {
    public var light: PaletteColor
    public var dark: PaletteColor

    public init(light: PaletteColor, dark: PaletteColor) {
        self.light = light
        self.dark = dark
    }
}

public enum AccentPalettes {
    public static let signal = AccentPalette(
        light: PaletteColor(red: 0.69, green: 0, blue: 0.06),
        dark: PaletteColor(red: 0.94, green: 0.24, blue: 0.28)
    )

    /// `nil` means the accent follows the primary text or the current artwork.
    public static func palette(for preference: AccentPreference) -> AccentPalette? {
        switch preference {
        case .mono:
            AccentPalette(light: ThemePalette.light.primaryText, dark: ThemePalette.dark.primaryText)
        case .signal:
            signal
        case .amber:
            AccentPalette(
                light: PaletteColor(red: 0.54, green: 0.32, blue: 0),
                dark: PaletteColor(red: 1.0, green: 0.70, blue: 0.22)
            )
        case .mint:
            AccentPalette(
                light: PaletteColor(red: 0, green: 0.40, blue: 0.31),
                dark: PaletteColor(red: 0.36, green: 0.90, blue: 0.75)
            )
        case .blue:
            AccentPalette(
                light: PaletteColor(red: 0, green: 0.34, blue: 0.72),
                dark: PaletteColor(red: 0.38, green: 0.69, blue: 1.0)
            )
        case .violet:
            AccentPalette(
                light: PaletteColor(red: 0.42, green: 0.18, blue: 0.75),
                dark: PaletteColor(red: 0.76, green: 0.61, blue: 1.0)
            )
        case .artwork:
            nil
        }
    }
}

public enum AccentContrast {
    public static let minimumRatio = 3.0

    /// Keeps the artwork hue direction while moving the color toward white or
    /// black until indicators reach the minimum contrast. Neutral input stays
    /// neutral because every channel moves by the same amount.
    public static func clamp(
        _ color: ArtworkTintColor,
        against background: PaletteColor
    ) -> ArtworkTintColor {
        let channels = (
            min(max(color.red, 0), 1),
            min(max(color.green, 0), 1),
            min(max(color.blue, 0), 1)
        )
        let start = PaletteColor(red: channels.0, green: channels.1, blue: channels.2)
        guard ThemePalette.contrastRatio(start, background) < minimumRatio else {
            return ArtworkTintColor(red: channels.0, green: channels.1, blue: channels.2)
        }

        let target = luminance(background) < 0.5 ? 1.0 : 0.0
        for step in stride(from: 0.05, through: 1.0, by: 0.05) {
            let mixed = (
                channels.0 + (target - channels.0) * step,
                channels.1 + (target - channels.1) * step,
                channels.2 + (target - channels.2) * step
            )
            let candidate = PaletteColor(red: mixed.0, green: mixed.1, blue: mixed.2)
            if ThemePalette.contrastRatio(candidate, background) >= minimumRatio {
                return ArtworkTintColor(red: mixed.0, green: mixed.1, blue: mixed.2)
            }
        }
        return ArtworkTintColor(red: target, green: target, blue: target)
    }

    /// Black or white, whichever reads better on a filled accent control.
    public static func foreground(for accent: PaletteColor) -> PaletteColor {
        let black = PaletteColor.gray(0)
        let white = PaletteColor.gray(1)
        return ThemePalette.contrastRatio(accent, black) >= ThemePalette.contrastRatio(accent, white)
            ? black
            : white
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

public struct AccentSettings {
    public static let storageKey = "accent.preference"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Unknown values fall back to Signal, the current accent.
    public var preference: AccentPreference {
        guard let raw = defaults.string(forKey: Self.storageKey),
              let preference = AccentPreference(rawValue: raw) else { return .signal }
        return preference
    }

    public func setPreference(_ preference: AccentPreference) {
        defaults.set(preference.rawValue, forKey: Self.storageKey)
    }

    public func reset() {
        defaults.removeObject(forKey: Self.storageKey)
    }
}
