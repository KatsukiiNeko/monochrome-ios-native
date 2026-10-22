// RepeatModeTests.swift: the pure end-of-track decision table.
import Foundation
import Testing
@testable import MonochromeCore

@Suite("EndOfTrackDecision")
struct RepeatModeTests {
    @Test func offAdvancesThenStops() {
        #expect(EndOfTrackDecision.action(repeatMode: .off, hasNext: true, hasTracks: true, itemIsLocal: false) == .advance)
        #expect(EndOfTrackDecision.action(repeatMode: .off, hasNext: false, hasTracks: true, itemIsLocal: false) == .stop)
    }

    @Test func allWrapsAtTheEnd() {
        #expect(EndOfTrackDecision.action(repeatMode: .all, hasNext: true, hasTracks: true, itemIsLocal: false) == .advance)
        #expect(EndOfTrackDecision.action(repeatMode: .all, hasNext: false, hasTracks: true, itemIsLocal: false) == .wrap)
    }

    @Test func oneReplaysTheCurrentTrack() {
        #expect(EndOfTrackDecision.action(repeatMode: .one, hasNext: true, hasTracks: true, itemIsLocal: true) == .replayInPlace)
        #expect(EndOfTrackDecision.action(repeatMode: .one, hasNext: true, hasTracks: true, itemIsLocal: false) == .reload)
    }

    @Test func cycleOrderIsOffAllOne() {
        #expect(RepeatMode.off.next == .all)
        #expect(RepeatMode.all.next == .one)
        #expect(RepeatMode.one.next == .off)
    }
}
