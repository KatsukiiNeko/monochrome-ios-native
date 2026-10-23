// DotMatrixTests.swift: glyph table shape and deterministic lookup.
import Testing
@testable import MonochromeCore

@Suite("DotMatrix")
struct DotMatrixTests {
    private let required = Array("0123456789/ACEHLOST")

    @Test func everyRequiredGlyphIsFiveBySeven() {
        for character in required {
            let glyph = DotMatrix.glyph(for: character)
            #expect(glyph != nil, "missing glyph for \(character)")
            #expect(glyph?.width == 5)
            #expect(glyph?.height == 7)
            #expect(glyph?.rows.count == 7)
            #expect(glyph?.isWellFormed == true)
        }
    }

    @Test func glyphsOnlyUseDotsAndHashes() {
        for character in required {
            let rows = DotMatrix.glyph(for: character)?.rows ?? []
            for row in rows {
                #expect(row.count == 5)
                #expect(row.allSatisfy { $0 == "#" || $0 == "." })
            }
        }
    }

    @Test func lookupIsDeterministic() {
        let first = DotMatrix.glyph(for: "A")
        let second = DotMatrix.glyph(for: "A")
        #expect(first == second)
        #expect(first?.rows[0] == ".###.")
        #expect(first?.rows[3] == "#####")
    }

    @Test func supportsKnownText() {
        #expect(DotMatrix.supports("0123456789"))
        #expect(DotMatrix.supports("ACEHLOST"))
        #expect(DotMatrix.supports("12/48"))
        #expect(DotMatrix.supports(""))
    }

    @Test func unsupportedCharacterReturnsNil() {
        #expect(DotMatrix.glyph(for: "B") == nil)
        #expect(DotMatrix.glyph(for: "Z") == nil)
        #expect(DotMatrix.glyph(for: "a") == nil)
        #expect(DotMatrix.supports("B") == false)
        #expect(DotMatrix.supports("A1Z") == false)
    }
}
