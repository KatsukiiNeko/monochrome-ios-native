// DotMatrix.swift: 5x7 dot-matrix glyphs for display-style labels.
public struct DotGlyph: Equatable, Sendable {
    public let rows: [String]
    public let width: Int
    public let height: Int
    public let isWellFormed: Bool

    public init(rows: [String]) {
        self.rows = rows
        self.width = rows.map(\.count).max() ?? 0
        self.height = rows.count
        self.isWellFormed = rows.count == 7 && rows.allSatisfy { row in
            row.count == 5 && row.allSatisfy { $0 == "#" || $0 == "." }
        }
    }
}

public enum DotMatrix {
    /// Empty text is supported; every character in non-empty text must have a glyph.
    public static func supports(_ text: String) -> Bool {
        text.allSatisfy { glyphs[$0] != nil }
    }

    public static func glyph(for character: Character) -> DotGlyph? {
        glyphs[character]
    }

    private static let glyphs: [Character: DotGlyph] = [
        "0": DotGlyph(rows: [
            ".###.",
            "#...#",
            "#..##",
            "#.#.#",
            "##..#",
            "#...#",
            ".###.",
        ]),
        "1": DotGlyph(rows: [
            "..#..",
            ".##..",
            "..#..",
            "..#..",
            "..#..",
            "..#..",
            ".###.",
        ]),
        "2": DotGlyph(rows: [
            ".###.",
            "#...#",
            "....#",
            "...#.",
            "..#..",
            ".#...",
            "#####",
        ]),
        "3": DotGlyph(rows: [
            "####.",
            "....#",
            "....#",
            ".###.",
            "....#",
            "....#",
            "####.",
        ]),
        "4": DotGlyph(rows: [
            "...#.",
            "..##.",
            ".#.#.",
            "#..#.",
            "#####",
            "...#.",
            "...#.",
        ]),
        "5": DotGlyph(rows: [
            "#####",
            "#....",
            "####.",
            "....#",
            "....#",
            "#...#",
            ".###.",
        ]),
        "6": DotGlyph(rows: [
            "..##.",
            ".#...",
            "#....",
            "####.",
            "#...#",
            "#...#",
            ".###.",
        ]),
        "7": DotGlyph(rows: [
            "#####",
            "....#",
            "...#.",
            "..#..",
            ".#...",
            ".#...",
            ".#...",
        ]),
        "8": DotGlyph(rows: [
            ".###.",
            "#...#",
            "#...#",
            ".###.",
            "#...#",
            "#...#",
            ".###.",
        ]),
        "9": DotGlyph(rows: [
            ".###.",
            "#...#",
            "#...#",
            ".####",
            "....#",
            "...#.",
            ".##..",
        ]),
        "/": DotGlyph(rows: [
            "....#",
            "....#",
            "...#.",
            "..#..",
            ".#...",
            "#....",
            "#....",
        ]),
        "A": DotGlyph(rows: [
            ".###.",
            "#...#",
            "#...#",
            "#####",
            "#...#",
            "#...#",
            "#...#",
        ]),
        "C": DotGlyph(rows: [
            ".###.",
            "#...#",
            "#....",
            "#....",
            "#....",
            "#...#",
            ".###.",
        ]),
        "E": DotGlyph(rows: [
            "#####",
            "#....",
            "#....",
            "####.",
            "#....",
            "#....",
            "#####",
        ]),
        "H": DotGlyph(rows: [
            "#...#",
            "#...#",
            "#...#",
            "#####",
            "#...#",
            "#...#",
            "#...#",
        ]),
        "L": DotGlyph(rows: [
            "#....",
            "#....",
            "#....",
            "#....",
            "#....",
            "#....",
            "#####",
        ]),
        "O": DotGlyph(rows: [
            ".###.",
            "#...#",
            "#...#",
            "#...#",
            "#...#",
            "#...#",
            ".###.",
        ]),
        "S": DotGlyph(rows: [
            ".####",
            "#....",
            "#....",
            ".###.",
            "....#",
            "....#",
            "####.",
        ]),
        "T": DotGlyph(rows: [
            "#####",
            "..#..",
            "..#..",
            "..#..",
            "..#..",
            "..#..",
            "..#..",
        ]),
    ]
}
