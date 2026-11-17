// ThemeDefinition.swift: portable theme tokens, presets, contrast validation and JSON.
import Foundation

/// One token, stored as normalized RGBA. Decoding clamps, so a hand-edited file
/// cannot produce an out-of-range color.
public struct ThemeColor: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
        self.alpha = Self.clamp(alpha)
    }

    public init(_ color: PaletteColor) {
        self.init(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }

    public var paletteColor: PaletteColor {
        PaletteColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    private enum CodingKeys: String, CodingKey { case red, green, blue, alpha }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            red: try container.decode(Double.self, forKey: .red),
            green: try container.decode(Double.self, forKey: .green),
            blue: try container.decode(Double.self, forKey: .blue),
            alpha: try container.decodeIfPresent(Double.self, forKey: .alpha) ?? 1
        )
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

public struct ThemeColors: Codable, Equatable, Sendable {
    public var background: ThemeColor
    public var surface: ThemeColor
    public var elevated: ThemeColor
    public var sunken: ThemeColor
    public var border: ThemeColor
    public var separator: ThemeColor
    public var primaryText: ThemeColor
    public var secondaryText: ThemeColor
    public var tertiaryText: ThemeColor
    public var accent: ThemeColor
    public var destructive: ThemeColor

    public init(
        background: ThemeColor,
        surface: ThemeColor,
        elevated: ThemeColor,
        sunken: ThemeColor,
        border: ThemeColor,
        separator: ThemeColor,
        primaryText: ThemeColor,
        secondaryText: ThemeColor,
        tertiaryText: ThemeColor,
        accent: ThemeColor,
        destructive: ThemeColor
    ) {
        self.background = background
        self.surface = surface
        self.elevated = elevated
        self.sunken = sunken
        self.border = border
        self.separator = separator
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.tertiaryText = tertiaryText
        self.accent = accent
        self.destructive = destructive
    }

    public init(_ palette: Palette) {
        self.init(
            background: ThemeColor(palette.background),
            surface: ThemeColor(palette.surface),
            elevated: ThemeColor(palette.elevated),
            sunken: ThemeColor(palette.sunken),
            border: ThemeColor(palette.border),
            separator: ThemeColor(palette.separator),
            primaryText: ThemeColor(palette.primaryText),
            secondaryText: ThemeColor(palette.secondaryText),
            tertiaryText: ThemeColor(palette.tertiaryText),
            accent: ThemeColor(palette.accent),
            destructive: ThemeColor(palette.destructive)
        )
    }

    public func palette() -> Palette {
        Palette(
            background: background.paletteColor,
            surface: surface.paletteColor,
            elevated: elevated.paletteColor,
            sunken: sunken.paletteColor,
            accentSurface: PaletteColor(
                red: accent.red,
                green: accent.green,
                blue: accent.blue,
                alpha: 0.14
            ),
            border: border.paletteColor,
            separator: separator.paletteColor,
            primaryText: primaryText.paletteColor,
            secondaryText: secondaryText.paletteColor,
            tertiaryText: tertiaryText.paletteColor,
            accent: accent.paletteColor,
            destructive: destructive.paletteColor
        )
    }

    public var primaryContrast: Double {
        ThemePalette.contrastRatio(primaryText.paletteColor, background.paletteColor)
    }

    public var surfaceContrast: Double {
        ThemePalette.contrastRatio(primaryText.paletteColor, surface.paletteColor)
    }
}

public struct ThemeDefinition: Codable, Equatable, Sendable, Identifiable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var id: String
    public var name: String
    /// True when the dark palette uses a fully black background.
    public var isPureBlack: Bool
    public var light: ThemeColors
    public var dark: ThemeColors

    public init(
        schemaVersion: Int = ThemeDefinition.schemaVersion,
        id: String,
        name: String,
        isPureBlack: Bool = false,
        light: ThemeColors,
        dark: ThemeColors
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.isPureBlack = isPureBlack
        self.light = light
        self.dark = dark
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, name, isPureBlack, light, dark
    }

    /// A file without a version is treated as version 0 and validated like any other.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? "imported"
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        isPureBlack = try container.decodeIfPresent(Bool.self, forKey: .isPureBlack) ?? false
        light = try container.decode(ThemeColors.self, forKey: .light)
        dark = try container.decode(ThemeColors.self, forKey: .dark)
    }
}

public enum ThemeValidationError: LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case emptyName
    case lowContrast(mode: String, ratio: Double)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            "This theme uses format version \(version), which this app cannot read."
        case .emptyName:
            "The theme needs a name."
        case .lowContrast(let mode, let ratio):
            "The \(mode) primary text contrast is \(String(format: "%.1f", ratio)):1. A theme needs at least 4.5:1."
        }
    }
}

public enum ThemeCodec {
    public static let minimumPrimaryContrast = 4.5

    /// Primary text must stay readable in both appearances, on the background and
    /// on cards. Everything else is accepted as authored.
    public static func validate(_ theme: ThemeDefinition) throws {
        guard theme.schemaVersion <= ThemeDefinition.schemaVersion else {
            throw ThemeValidationError.unsupportedVersion(theme.schemaVersion)
        }
        guard !theme.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ThemeValidationError.emptyName
        }
        for (mode, colors) in [("light", theme.light), ("dark", theme.dark)] {
            let background = colors.primaryContrast
            guard background >= minimumPrimaryContrast else {
                throw ThemeValidationError.lowContrast(mode: mode, ratio: background)
            }
            let surface = colors.surfaceContrast
            guard surface >= minimumPrimaryContrast else {
                throw ThemeValidationError.lowContrast(mode: "\(mode) card", ratio: surface)
            }
        }
    }

    public static func decode(_ data: Data) throws -> ThemeDefinition {
        let theme = try JSONDecoder().decode(ThemeDefinition.self, from: data)
        try validate(theme)
        return theme
    }

    public static func encode(_ theme: ThemeDefinition) throws -> Data {
        try validate(theme)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(theme)
    }
}

public enum ThemePresets {
    public static let monochrome = ThemeDefinition(
        id: "monochrome",
        name: "Monochrome",
        light: ThemeColors(ThemePalette.light),
        dark: ThemeColors(ThemePalette.dark)
    )

    /// Pure black in dark appearance: OLED pixels turn off and text keeps natural contrast.
    public static let oled = ThemeDefinition(
        id: "oled",
        name: "OLED Black",
        isPureBlack: true,
        light: monochrome.light,
        dark: ThemeColors(
            background: ThemeColor(red: 0, green: 0, blue: 0),
            surface: ThemeColor(red: 0.04, green: 0.04, blue: 0.04),
            elevated: ThemeColor(red: 0.09, green: 0.09, blue: 0.09),
            sunken: ThemeColor(red: 0.02, green: 0.02, blue: 0.02),
            border: ThemeColor(red: 1, green: 1, blue: 1, alpha: 0.16),
            separator: ThemeColor(red: 1, green: 1, blue: 1, alpha: 0.10),
            primaryText: ThemeColor(red: 0.98, green: 0.98, blue: 0.98),
            secondaryText: ThemeColor(red: 0.72, green: 0.72, blue: 0.72),
            tertiaryText: ThemeColor(red: 0.56, green: 0.56, blue: 0.56),
            accent: ThemeColor(red: 0.94, green: 0.24, blue: 0.28),
            destructive: ThemeColor(red: 0.98, green: 0.36, blue: 0.38)
        )
    )

    /// Warm paper for light appearance; the dark side stays the standard one.
    public static let paper = ThemeDefinition(
        id: "paper",
        name: "Paper",
        light: ThemeColors(
            background: ThemeColor(red: 0.96, green: 0.94, blue: 0.89),
            surface: ThemeColor(red: 0.91, green: 0.89, blue: 0.84),
            elevated: ThemeColor(red: 0.98, green: 0.97, blue: 0.94),
            sunken: ThemeColor(red: 0.87, green: 0.85, blue: 0.80),
            border: ThemeColor(red: 0.24, green: 0.20, blue: 0.14, alpha: 0.18),
            separator: ThemeColor(red: 0.24, green: 0.20, blue: 0.14, alpha: 0.12),
            primaryText: ThemeColor(red: 0.10, green: 0.08, blue: 0.05),
            secondaryText: ThemeColor(red: 0.34, green: 0.30, blue: 0.25),
            tertiaryText: ThemeColor(red: 0.48, green: 0.44, blue: 0.39),
            accent: ThemeColor(red: 0.55, green: 0.16, blue: 0.12),
            destructive: ThemeColor(red: 0.60, green: 0.10, blue: 0.10)
        ),
        dark: ThemeColors(ThemePalette.dark)
    )

    /// Neutral gray without the default accent hue in either appearance.
    public static let graphite = ThemeDefinition(
        id: "graphite",
        name: "Graphite",
        light: ThemeColors(
            background: ThemeColor(red: 0.90, green: 0.90, blue: 0.91),
            surface: ThemeColor(red: 0.85, green: 0.85, blue: 0.86),
            elevated: ThemeColor(red: 0.95, green: 0.95, blue: 0.96),
            sunken: ThemeColor(red: 0.80, green: 0.80, blue: 0.82),
            border: ThemeColor(red: 0, green: 0, blue: 0, alpha: 0.16),
            separator: ThemeColor(red: 0, green: 0, blue: 0, alpha: 0.10),
            primaryText: ThemeColor(red: 0.08, green: 0.08, blue: 0.09),
            secondaryText: ThemeColor(red: 0.33, green: 0.33, blue: 0.35),
            tertiaryText: ThemeColor(red: 0.47, green: 0.47, blue: 0.49),
            accent: ThemeColor(red: 0.25, green: 0.25, blue: 0.27),
            destructive: ThemeColor(red: 0.64, green: 0.10, blue: 0.10)
        ),
        dark: ThemeColors(
            background: ThemeColor(red: 0.07, green: 0.07, blue: 0.08),
            surface: ThemeColor(red: 0.12, green: 0.12, blue: 0.13),
            elevated: ThemeColor(red: 0.17, green: 0.17, blue: 0.18),
            sunken: ThemeColor(red: 0.09, green: 0.09, blue: 0.10),
            border: ThemeColor(red: 1, green: 1, blue: 1, alpha: 0.14),
            separator: ThemeColor(red: 1, green: 1, blue: 1, alpha: 0.10),
            primaryText: ThemeColor(red: 0.96, green: 0.96, blue: 0.97),
            secondaryText: ThemeColor(red: 0.70, green: 0.70, blue: 0.72),
            tertiaryText: ThemeColor(red: 0.55, green: 0.55, blue: 0.57),
            accent: ThemeColor(red: 0.86, green: 0.86, blue: 0.88),
            destructive: ThemeColor(red: 0.96, green: 0.38, blue: 0.38)
        )
    )

    public static var all: [ThemeDefinition] { [monochrome, oled, paper, graphite] }

    public static func theme(id: String) -> ThemeDefinition? {
        all.first { $0.id == id }
    }
}

public struct ThemeSettings {
    public static let selectedIDKey = "theme.selectedID"
    public static let customThemeKey = "theme.customTheme"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var selectedID: String {
        defaults.string(forKey: Self.selectedIDKey) ?? ThemePresets.monochrome.id
    }

    public var custom: ThemeDefinition? {
        guard let data = defaults.data(forKey: Self.customThemeKey) else { return nil }
        return try? ThemeCodec.decode(data)
    }

    /// A preset, then a previously imported theme, then the default.
    public var current: ThemeDefinition {
        if let preset = ThemePresets.theme(id: selectedID) { return preset }
        if let custom, custom.id == selectedID { return custom }
        return ThemePresets.monochrome
    }

    public func selectPreset(id: String) {
        guard ThemePresets.theme(id: id) != nil else { return }
        defaults.set(id, forKey: Self.selectedIDKey)
    }

    /// Validates, stores and selects an imported theme. A rejected file leaves the
    /// current selection untouched.
    @discardableResult
    public func importTheme(_ data: Data) throws -> ThemeDefinition {
        var theme = try ThemeCodec.decode(data)
        theme.schemaVersion = ThemeDefinition.schemaVersion
        // Imported themes get a fresh id so they never shadow a preset.
        theme.id = "custom-\(UUID().uuidString)"
        let encoded = try ThemeCodec.encode(theme)
        defaults.set(encoded, forKey: Self.customThemeKey)
        defaults.set(theme.id, forKey: Self.selectedIDKey)
        return theme
    }

    public func exportData(for theme: ThemeDefinition) throws -> Data {
        try ThemeCodec.encode(theme)
    }

    public func reset() {
        defaults.removeObject(forKey: Self.selectedIDKey)
        defaults.removeObject(forKey: Self.customThemeKey)
    }
}
