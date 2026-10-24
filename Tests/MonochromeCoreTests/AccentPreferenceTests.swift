// AccentPreferenceTests.swift: persisted accent choices and contrast guarantees.
import Foundation
import Testing
@testable import MonochromeCore

@Suite("AccentPreference")
struct AccentPreferenceTests {
    @Test func defaultsToSignalAndPersists() throws {
        let suite = "monochrome-accent-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AccentSettings(defaults: defaults)

        #expect(settings.preference == .signal)
        settings.setPreference(.mint)
        #expect(AccentSettings(defaults: defaults).preference == .mint)
    }

    @Test func unknownValueFallsBackToSignal() throws {
        let suite = "monochrome-accent-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("chartreuse", forKey: AccentSettings.storageKey)

        #expect(AccentSettings(defaults: defaults).preference == .signal)
    }

    @Test func everyPresetMeetsContrastOnBackgroundAndSurface() {
        for preference in AccentPreference.allCases where preference != .artwork {
            let palette = AccentPalettes.palette(for: preference)!
            for (accent, theme) in [
                (palette.light, ThemePalette.light),
                (palette.dark, ThemePalette.dark)
            ] {
                #expect(ThemePalette.contrastRatio(accent, theme.background) >= 4.5)
                #expect(ThemePalette.contrastRatio(accent, theme.surface) >= 4.5)
            }
        }
    }

    @Test func artworkAccentIsClampedForBothAppearances() {
        let darkArtwork = ArtworkTintColor(red: 0.02, green: 0.03, blue: 0.04)
        let lightArtwork = ArtworkTintColor(red: 0.98, green: 0.97, blue: 0.96)
        let darkOutput = AccentContrast.clamp(darkArtwork, against: ThemePalette.dark.surface)
        let lightOutput = AccentContrast.clamp(lightArtwork, against: ThemePalette.light.surface)

        #expect(ThemePalette.contrastRatio(
            PaletteColor(red: darkOutput.red, green: darkOutput.green, blue: darkOutput.blue),
            ThemePalette.dark.surface
        ) >= AccentContrast.minimumRatio)
        #expect(ThemePalette.contrastRatio(
            PaletteColor(red: lightOutput.red, green: lightOutput.green, blue: lightOutput.blue),
            ThemePalette.light.surface
        ) >= AccentContrast.minimumRatio)
    }

    @Test func neutralArtworkStaysNeutralAndStable() {
        let gray = ArtworkTintColor(red: 0.12, green: 0.12, blue: 0.12)
        let first = AccentContrast.clamp(gray, against: ThemePalette.dark.surface)
        let second = AccentContrast.clamp(gray, against: ThemePalette.dark.surface)

        #expect(first == second)
        #expect(first.red == first.green)
        #expect(first.green == first.blue)
    }

    @Test func artworkMissingMeansTheDefaultPaletteIsAvailable() {
        #expect(AccentPalettes.palette(for: .artwork) == nil)
        #expect(AccentPalettes.palette(for: .signal) == AccentPalettes.signal)
    }

    @Test func foregroundReadsOnEveryAccent() {
        for preference in AccentPreference.allCases where preference != .artwork {
            let palette = AccentPalettes.palette(for: preference)!
            for accent in [palette.light, palette.dark] {
                #expect(ThemePalette.contrastRatio(AccentContrast.foreground(for: accent), accent) >= 4.5)
            }
        }
    }
}
