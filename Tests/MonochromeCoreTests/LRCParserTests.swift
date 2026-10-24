// LRCParserTests.swift: table tests for tolerant LRC parsing.
import Foundation
import Testing
@testable import MonochromeCore

@Suite("LRCParser")
struct LRCParserTests {
    @Test func timestampsOffsetsMetadataAndBlankLines() {
        let lrc = """
        [ti:Test Song]
        [ar:Test Artist]
        [offset:+500]
        [00:01.50]First synthetic line
        [00:03]Second synthetic line
        [00:04.250][00:06.000]Repeated synthetic line
        [00:08.00]
        [00:09.00]<00:09.10>Word <00:09.50>timed line
        """

        let lines = LRCParser.parse(lrc)

        #expect(lines.map(\.time) == [2.0, 3.5, 4.75, 6.5, 8.5, 9.5])
        #expect(lines.map(\.text) == [
            "First synthetic line",
            "Second synthetic line",
            "Repeated synthetic line",
            "Repeated synthetic line",
            "",
            "Word timed line",
        ])
    }

    @Test func fractionDigitsAreTenthsHundredthsAndMilliseconds() {
        let lines = LRCParser.parse("""
        [00:01.5]One
        [00:02.50]Two
        [00:03.500]Three
        [00:04]Four
        """)

        #expect(lines.map(\.time) == [1.5, 2.5, 3.5, 4.0])
    }

    @Test func negativeOffsetShiftsAndClampsAtZero() {
        let lines = LRCParser.parse("""
        [offset:-1000]
        [00:00.500]Clamped
        [00:02.000]Shifted
        """)

        #expect(lines.map(\.time) == [0, 1.0])
    }

    @Test func crlfAndBOMAreAccepted() {
        let text = "\u{FEFF}[00:01.00]Line one\r\n[00:02.00]Line two\r\n"
        let lines = LRCParser.parse(text)
        #expect(lines.map(\.text) == ["Line one", "Line two"])
    }

    @Test func metadataAndLinesWithoutTimestampsAreIgnored() {
        let lines = LRCParser.parse("""
        [ti:Title]
        [al:Album]
        [by:Someone]
        plain text that is not timed
        [00:05.00]Only timed line
        """)

        #expect(lines == [LyricLine(time: 5, text: "Only timed line")])
    }

    @Test func outputIsSortedByTime() {
        let lines = LRCParser.parse("""
        [00:30.00]Third
        [00:10.00]First
        [00:20.00]Second
        """)

        #expect(lines.map(\.text) == ["First", "Second", "Third"])
    }

    @Test func duplicateTimestampsKeepTheirInputOrder() {
        let lines = LRCParser.parse("""
        [00:10.00]First duplicate
        [00:10.00]Second duplicate
        """)

        #expect(lines.map(\.text) == ["First duplicate", "Second duplicate"])
    }

    @Test func malformedInputNeverThrowsOrInventsLines() {
        let inputs = [
            "",
            "garbage",
            "[",
            "[]",
            "[00:10",
            "[00:10.00",
            "[00:60.00]Seconds out of range",
            "[99:99]Minutes and seconds out of range",
            "[abc:def]Not a timestamp",
            "[-1:00]Negative minutes",
            "[:10]Missing minutes",
            "<not a word tag>",
            "\u{0000}\u{0001}\u{FFFD}",
        ]

        for input in inputs {
            #expect(LRCParser.parse(input).isEmpty, "unexpected lines for \(input.debugDescription)")
        }
    }

    @Test func aVeryLongLineDoesNotCrash() {
        let longText = String(repeating: "synthetic ", count: 20_000)
        let lines = LRCParser.parse("[00:01.00]\(longText)")

        #expect(lines.count == 1)
        #expect(lines[0].text.hasPrefix("synthetic synthetic"))
        #expect(!lines[0].text.isEmpty)
    }

    @Test func nonLatinTextIsPreserved() {
        let lines = LRCParser.parse("[00:01.00]日本語のテスト · kiểm tra")
        #expect(lines == [LyricLine(time: 1, text: "日本語のテスト · kiểm tra")])
    }
}
