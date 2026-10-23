// ArtworkTintTests.swift: derivation rules for dark, readable artwork surfaces.
import Testing
@testable import MonochromeCore

@Suite("ArtworkTint")
struct ArtworkTintTests {
    @Test func brightArtworkIsDarkened() {
        let tint = ArtworkTint.derive(from: ArtworkTintColor(red: 1, green: 1, blue: 1))
        #expect(tint.red == ArtworkTint.maximumBrightness)
        #expect(tint.green == ArtworkTint.maximumBrightness)
        #expect(tint.blue == ArtworkTint.maximumBrightness)
    }

    @Test func darkArtworkIsNotPureBlack() {
        let tint = ArtworkTint.derive(from: ArtworkTintColor(red: 0, green: 0, blue: 0.02))
        #expect(tint.blue >= ArtworkTint.minimumBrightness)
        #expect(tint.blue > 0)
    }

    @Test func graysStayGray() {
        let tint = ArtworkTint.derive(from: ArtworkTintColor(red: 0.5, green: 0.5, blue: 0.5))
        #expect(tint.red == tint.green)
        #expect(tint.green == tint.blue)
    }

    @Test func hueIsPreserved() {
        let tint = ArtworkTint.derive(from: ArtworkTintColor(red: 0.8, green: 0.1, blue: 0.1))
        #expect(tint.red > tint.green)
        #expect(tint.red > tint.blue)
    }

    @Test func outputIsDeterministic() {
        let input = ArtworkTintColor(red: 0.2, green: 0.5, blue: 0.9)
        #expect(ArtworkTint.derive(from: input) == ArtworkTint.derive(from: input))
    }

    @Test func neutralFallbackIsDarkGray() {
        #expect(ArtworkTintColor.neutral.red == ArtworkTintColor.neutral.green)
        #expect(ArtworkTintColor.neutral.green == ArtworkTintColor.neutral.blue)
        #expect(ArtworkTintColor.neutral.red >= ArtworkTint.minimumBrightness)
    }
}
