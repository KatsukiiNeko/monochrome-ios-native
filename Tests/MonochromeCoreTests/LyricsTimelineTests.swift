// LyricsTimelineTests.swift: active-line lookup and boundary behavior.
import Foundation
import Testing
@testable import MonochromeCore

@Suite("LyricsTimeline")
struct LyricsTimelineTests {
    private let lines = [
        LyricLine(time: 0, text: "Zero"),
        LyricLine(time: 5, text: "Five"),
        LyricLine(time: 10, text: "Ten"),
    ]

    @Test func beforeTheFirstLineThereIsNoActiveLine() {
        #expect(LyricsTimeline.activeIndex(in: lines, position: -1) == nil)
        #expect(LyricsTimeline.activeIndex(in: lines, position: -0.16) == nil)
    }

    @Test func exactTimestampsSelectTheirLine() {
        #expect(LyricsTimeline.activeIndex(in: lines, position: 0) == 0)
        #expect(LyricsTimeline.activeIndex(in: lines, position: 5) == 1)
        #expect(LyricsTimeline.activeIndex(in: lines, position: 10) == 2)
    }

    @Test func betweenLinesKeepsThePreviousLine() {
        #expect(LyricsTimeline.activeIndex(in: lines, position: 4.8) == 0)
        #expect(LyricsTimeline.activeIndex(in: lines, position: 4.9) == 1)
        #expect(LyricsTimeline.activeIndex(in: lines, position: 9.99) == 2)
    }

    @Test func afterTheLastLineKeepsTheLastLine() {
        #expect(LyricsTimeline.activeIndex(in: lines, position: 500) == 2)
    }

    @Test func theLeadMakesALineAppearEarly() {
        #expect(LyricsTimeline.activeIndex(in: lines, position: 4.7, lead: 0) == 0)
        #expect(LyricsTimeline.activeIndex(in: lines, position: 4.7, lead: 0.4) == 1)
        #expect(LyricsTimeline.activeIndex(in: lines, position: 4.7, lead: -0.4) == 0)
    }

    @Test func theOffsetShiftsTheWholeTrack() {
        #expect(LyricsTimeline.activeIndex(in: lines, position: 4, offset: 1) == 1)
        #expect(LyricsTimeline.activeIndex(in: lines, position: 4, offset: -1) == 0)
    }

    @Test func emptyAndUnsortedInputReturnNoLine() {
        #expect(LyricsTimeline.activeIndex(in: [], position: 5) == nil)

        let unsorted = [
            LyricLine(time: 10, text: "Ten"),
            LyricLine(time: 5, text: "Five"),
        ]
        #expect(LyricsTimeline.isSorted(unsorted) == false)
        #expect(LyricsTimeline.activeIndex(in: unsorted, position: 12) == nil)
        #expect(LyricsTimeline.isSorted(lines))
    }

    @Test func duplicateTimestampsResolveToTheLastOne() {
        let duplicates = [
            LyricLine(time: 3, text: "First"),
            LyricLine(time: 3, text: "Second"),
        ]
        #expect(LyricsTimeline.activeIndex(in: duplicates, position: 3) == 1)
    }

    @Test func singleLineCases() {
        let one = [LyricLine(time: 2, text: "Only")]
        #expect(LyricsTimeline.activeIndex(in: one, position: 1.8, lead: 0) == nil)
        #expect(LyricsTimeline.activeIndex(in: one, position: 1.95, lead: 0.1) == 0)
        #expect(LyricsTimeline.activeIndex(in: one, position: 2) == 0)
    }
}
