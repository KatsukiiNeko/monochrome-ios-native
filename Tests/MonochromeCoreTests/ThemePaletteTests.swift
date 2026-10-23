// ThemePaletteTests.swift: contrast guarantees and alpha compositing for both palettes.
import Testing
@testable import MonochromeCore

@Suite("ThemePalette")
struct ThemePaletteTests {
    @Test func primaryAndSecondaryTextMeetContrast() {
        for palette in [ThemePalette.light, ThemePalette.dark] {
            #expect(ThemePalette.contrastRatio(palette.primaryText, palette.background) >= 4.5)
            #expect(ThemePalette.contrastRatio(palette.primaryText, palette.surface) >= 4.5)
            #expect(ThemePalette.contrastRatio(palette.secondaryText, palette.background) >= 4.5)
            #expect(ThemePalette.contrastRatio(palette.secondaryText, palette.surface) >= 4.5)
        }
    }

    @Test func accentMeetsNonTextContrast() {
        for palette in [ThemePalette.light, ThemePalette.dark] {
            #expect(ThemePalette.contrastRatio(palette.accent, palette.surface) >= 3.0)
        }
    }

    @Test func lightAndDarkDiffer() {
        #expect(ThemePalette.light != ThemePalette.dark)
        #expect(ThemePalette.light.background != ThemePalette.dark.background)
        #expect(ThemePalette.light.primaryText != ThemePalette.dark.primaryText)
        #expect(ThemePalette.light.accent != ThemePalette.dark.accent)
    }

    @Test func contrastIsSymmetricAndMaximalForBlackOnWhite() {
        let black = PaletteColor.gray(0)
        let white = PaletteColor.gray(1)
        #expect(abs(ThemePalette.contrastRatio(black, white) - 21) < 0.01)
        #expect(ThemePalette.contrastRatio(black, white) == ThemePalette.contrastRatio(white, black))
    }

    @Test func translucentColorCompositesOverBackdrop() {
        let accent = ThemePalette.light.accent
        let surface = ThemePalette.light.surface
        let overlay = ThemePalette.light.accentSurface
        let flattened = overlay.composited(over: surface)

        #expect(flattened.alpha == 1)
        #expect(abs(flattened.red - (accent.red * overlay.alpha + surface.red * (1 - overlay.alpha))) < 1e-12)
        #expect(abs(flattened.green - (accent.green * overlay.alpha + surface.green * (1 - overlay.alpha))) < 1e-12)
        #expect(abs(flattened.blue - (accent.blue * overlay.alpha + surface.blue * (1 - overlay.alpha))) < 1e-12)
    }
}
