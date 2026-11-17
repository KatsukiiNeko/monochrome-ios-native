// ThemeDefinitionTests.swift: contrast rules, schema validation, round trip and selection.
import Foundation
import Testing
@testable import MonochromeCore

private func freshDefaults() -> UserDefaults {
    let name = "monochrome-theme-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name) ?? .standard
    defaults.removePersistentDomain(forName: name)
    return defaults
}

private func color(_ value: Double) -> ThemeColor {
    ThemeColor(red: value, green: value, blue: value)
}

private func theme(
    name: String = "Custom",
    schemaVersion: Int = ThemeDefinition.schemaVersion,
    background: Double,
    text: Double
) -> ThemeDefinition {
    ThemeDefinition(
        schemaVersion: schemaVersion,
        id: "custom",
        name: name,
        light: ThemeColors(
            background: color(background),
            surface: color(min(background + 0.04, 1)),
            elevated: color(min(background + 0.06, 1)),
            sunken: color(max(background - 0.04, 0)),
            border: color(0.5),
            separator: color(0.5),
            primaryText: color(text),
            secondaryText: color(text),
            tertiaryText: color(text),
            accent: color(0.5),
            destructive: color(0.5)
        ),
        dark: ThemeColors(
            background: color(1 - background),
            surface: color(max(1 - background - 0.04, 0)),
            elevated: color(max(1 - background - 0.08, 0)),
            sunken: color(min(1 - background + 0.04, 1)),
            border: color(0.5),
            separator: color(0.5),
            primaryText: color(1 - text),
            secondaryText: color(1 - text),
            tertiaryText: color(1 - text),
            accent: color(0.5),
            destructive: color(0.5)
        )
    )
}

@Suite("Theme presets")
struct ThemePresetTests {
    @Test("every preset passes validation in both appearances")
    func presetsAreValid() throws {
        for preset in ThemePresets.all {
            try ThemeCodec.validate(preset)
            #expect(preset.light.primaryContrast >= ThemeCodec.minimumPrimaryContrast)
            #expect(preset.dark.primaryContrast >= ThemeCodec.minimumPrimaryContrast)
        }
    }

    @Test("OLED uses a fully black dark background")
    func pureBlack() {
        #expect(ThemePresets.oled.isPureBlack)
        #expect(ThemePresets.oled.dark.background.red == 0)
        #expect(ThemePresets.oled.dark.background.green == 0)
        #expect(ThemePresets.oled.dark.background.blue == 0)
        #expect(!ThemePresets.monochrome.isPureBlack)
    }

    @Test("preset ids are unique and resolvable")
    func uniqueIdentifiers() {
        let ids = ThemePresets.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ThemePresets.theme(id: "oled")?.name == "OLED Black")
        #expect(ThemePresets.theme(id: "missing") == nil)
    }

    @Test("the palette conversion keeps every token")
    func paletteConversion() {
        let colors = ThemeColors(ThemePalette.dark)
        let palette = colors.palette()
        #expect(palette.background == ThemePalette.dark.background)
        #expect(palette.primaryText == ThemePalette.dark.primaryText)
        #expect(palette.accent == ThemePalette.dark.accent)
        #expect(palette.accentSurface.alpha == 0.14)
    }
}

@Suite("Theme validation")
struct ThemeValidationTests {
    @Test("a readable theme validates")
    func acceptsReadable() throws {
        try ThemeCodec.validate(theme(background: 0.98, text: 0.05))
    }

    @Test("low primary text contrast is rejected in either appearance")
    func rejectsLowContrast() {
        // Light text on a light background fails; the dark side mirrors it.
        let low = theme(background: 0.95, text: 0.85)
        #expect(throws: ThemeValidationError.lowContrast(mode: "light", ratio: low.light.primaryContrast)) {
            try ThemeCodec.validate(low)
        }
    }

    @Test("a newer format version is rejected")
    func rejectsNewerVersion() {
        let future = theme(schemaVersion: ThemeDefinition.schemaVersion + 1, background: 0.98, text: 0.05)
        #expect(throws: ThemeValidationError.unsupportedVersion(ThemeDefinition.schemaVersion + 1)) {
            try ThemeCodec.validate(future)
        }
    }

    @Test("a theme needs a name")
    func rejectsEmptyName() {
        let unnamed = theme(name: "   ", background: 0.98, text: 0.05)
        #expect(throws: ThemeValidationError.emptyName) {
            try ThemeCodec.validate(unnamed)
        }
    }

    @Test("out-of-range channels are clamped while decoding")
    func clampsChannels() throws {
        let json = """
        {
          "schemaVersion": 1,
          "id": "wild",
          "name": "Wild",
          "light": {
            "background": {"red": 2, "green": -1, "blue": 0.5},
            "surface": {"red": 0.9, "green": 0.9, "blue": 0.9},
            "elevated": {"red": 1, "green": 1, "blue": 1},
            "sunken": {"red": 0.8, "green": 0.8, "blue": 0.8},
            "border": {"red": 0, "green": 0, "blue": 0},
            "separator": {"red": 0, "green": 0, "blue": 0},
            "primaryText": {"red": 0, "green": 0, "blue": 0},
            "secondaryText": {"red": 0.3, "green": 0.3, "blue": 0.3},
            "tertiaryText": {"red": 0.5, "green": 0.5, "blue": 0.5},
            "accent": {"red": 0.6, "green": 0, "blue": 0},
            "destructive": {"red": 0.6, "green": 0, "blue": 0}
          },
          "dark": {
            "background": {"red": 0, "green": 0, "blue": 0},
            "surface": {"red": 0.04, "green": 0.04, "blue": 0.04},
            "elevated": {"red": 0.08, "green": 0.08, "blue": 0.08},
            "sunken": {"red": 0.02, "green": 0.02, "blue": 0.02},
            "border": {"red": 1, "green": 1, "blue": 1},
            "separator": {"red": 1, "green": 1, "blue": 1},
            "primaryText": {"red": 1, "green": 1, "blue": 1},
            "secondaryText": {"red": 0.7, "green": 0.7, "blue": 0.7},
            "tertiaryText": {"red": 0.5, "green": 0.5, "blue": 0.5},
            "accent": {"red": 1, "green": 0.2, "blue": 0.2},
            "destructive": {"red": 1, "green": 0.3, "blue": 0.3}
          }
        }
        """
        let decoded = try ThemeCodec.decode(Data(json.utf8))
        #expect(decoded.light.background.red == 1)
        #expect(decoded.light.background.green == 0)
        #expect(decoded.light.background.alpha == 1)
    }
}

@Suite("Theme import and export")
struct ThemeCodecTests {
    @Test("encode then decode returns the same theme")
    func roundTrip() throws {
        for preset in ThemePresets.all {
            let data = try ThemeCodec.encode(preset)
            let restored = try ThemeCodec.decode(data)
            #expect(restored == preset)
        }
    }

    @Test("malformed JSON is rejected")
    func rejectsMalformed() {
        #expect(throws: (any Error).self) {
            _ = try ThemeCodec.decode(Data("{not a theme".utf8))
        }
    }

    @Test("import stores and selects the theme, and export round trips it")
    func importAndExport() throws {
        let defaults = freshDefaults()
        let settings = ThemeSettings(defaults: defaults)
        #expect(settings.current.id == ThemePresets.monochrome.id)

        let source = theme(background: 0.98, text: 0.05)
        let data = try ThemeCodec.encode(source)
        let imported = try settings.importTheme(data)

        #expect(imported.id.hasPrefix("custom-"))
        #expect(settings.current.id == imported.id)
        #expect(settings.current.light.background == source.light.background)
        #expect(try ThemeCodec.decode(settings.exportData(for: settings.current)) == settings.current)
    }

    @Test("a rejected import keeps the previous selection")
    func rejectedImportKeepsSelection() throws {
        let defaults = freshDefaults()
        let settings = ThemeSettings(defaults: defaults)
        settings.selectPreset(id: "oled")

        // A failing theme cannot be encoded, so this is a hand-edited file.
        let lowContrastJSON = """
        {"schemaVersion":1,"id":"x","name":"Faint",
         "light":{"background":{"red":0.95,"green":0.95,"blue":0.95},
           "surface":{"red":0.95,"green":0.95,"blue":0.95},
           "elevated":{"red":1,"green":1,"blue":1},
           "sunken":{"red":0.9,"green":0.9,"blue":0.9},
           "border":{"red":0.5,"green":0.5,"blue":0.5},
           "separator":{"red":0.5,"green":0.5,"blue":0.5},
           "primaryText":{"red":0.85,"green":0.85,"blue":0.85},
           "secondaryText":{"red":0.85,"green":0.85,"blue":0.85},
           "tertiaryText":{"red":0.85,"green":0.85,"blue":0.85},
           "accent":{"red":0.5,"green":0.5,"blue":0.5},
           "destructive":{"red":0.5,"green":0.5,"blue":0.5}},
         "dark":{"background":{"red":0.05,"green":0.05,"blue":0.05},
           "surface":{"red":0.1,"green":0.1,"blue":0.1},
           "elevated":{"red":0.12,"green":0.12,"blue":0.12},
           "sunken":{"red":0.02,"green":0.02,"blue":0.02},
           "border":{"red":1,"green":1,"blue":1},
           "separator":{"red":1,"green":1,"blue":1},
           "primaryText":{"red":1,"green":1,"blue":1},
           "secondaryText":{"red":0.7,"green":0.7,"blue":0.7},
           "tertiaryText":{"red":0.5,"green":0.5,"blue":0.5},
           "accent":{"red":1,"green":0.2,"blue":0.2},
           "destructive":{"red":1,"green":0.3,"blue":0.3}}}
        """
        #expect(throws: (any Error).self) {
            _ = try settings.importTheme(Data(lowContrastJSON.utf8))
        }
        #expect(settings.current.id == "oled")
    }

    @Test("selecting a preset persists and reset returns to the default")
    func selectionPersists() {
        let defaults = freshDefaults()
        let settings = ThemeSettings(defaults: defaults)
        settings.selectPreset(id: "paper")
        #expect(ThemeSettings(defaults: defaults).current.id == "paper")
        settings.selectPreset(id: "not-a-preset")
        #expect(settings.current.id == "paper")
        settings.reset()
        #expect(settings.current.id == ThemePresets.monochrome.id)
    }
}
