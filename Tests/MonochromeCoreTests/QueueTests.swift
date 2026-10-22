// QueueTests.swift: host tests for the queue cursor, removal and reordering.
import Foundation
import Testing
@testable import MonochromeCore

private func makeTrack(_ id: String) -> Track {
    Track(id: id, title: "Track \(id)", fileName: "\(id).m4a")
}

@Suite("Queue")
struct QueueTests {
    @Test func replaceClampsStartingIndex() {
        var queue = Queue()
        queue.replace(with: [makeTrack("a"), makeTrack("b")], startingAt: 99)
        #expect(queue.current?.id == "b")

        queue.replace(with: [], startingAt: 0)
        #expect(queue.current == nil)
    }

    @Test func advanceStopsAtEndWithoutMovingCursor() {
        var queue = Queue(tracks: [makeTrack("a"), makeTrack("b")])
        #expect(queue.advance()?.id == "b")
        #expect(queue.advance() == nil)
        #expect(queue.current?.id == "b")
    }

    @Test func rewindStopsAtStart() {
        var queue = Queue(tracks: [makeTrack("a"), makeTrack("b")])
        #expect(queue.rewind() == nil)
        #expect(queue.jump(to: 1)?.id == "b")
        #expect(queue.rewind()?.id == "a")
        #expect(queue.jump(to: 5) == nil)
    }

    @Test func removingBeforeCurrentShiftsCursor() {
        var queue = Queue(tracks: [makeTrack("a"), makeTrack("b"), makeTrack("c")])
        queue.jump(to: 2)

        queue.remove(at: 0)

        #expect(queue.current?.id == "c")
        #expect(queue.tracks.map(\.id) == ["b", "c"])
    }

    @Test func removingCurrentSelectsFollowingTrack() {
        var queue = Queue(tracks: [makeTrack("a"), makeTrack("b"), makeTrack("c")])
        queue.jump(to: 1)

        queue.remove(at: 1)

        #expect(queue.current?.id == "c")
    }

    @Test func removingLastCurrentTrackClampsToNewEnd() {
        var queue = Queue(tracks: [makeTrack("a"), makeTrack("b")])
        queue.jump(to: 1)

        queue.remove(at: 1)

        #expect(queue.current?.id == "a")
    }

    @Test func removingEverythingClearsCursor() {
        var queue = Queue(tracks: [makeTrack("a")])
        queue.remove(at: 0)
        #expect(queue.current == nil)
        #expect(queue.isEmpty)
    }

    @Test func appendSetsCursorOnEmptyQueue() {
        var queue = Queue()
        queue.append([makeTrack("a")])
        #expect(queue.current?.id == "a")
    }

    @Test func moveKeepsCursorOnSameTrack() {
        var queue = Queue(tracks: [makeTrack("a"), makeTrack("b"), makeTrack("c")])
        queue.jump(to: 1)

        queue.move(from: 0, to: 3)

        #expect(queue.tracks.map(\.id) == ["b", "c", "a"])
        #expect(queue.current?.id == "b")
    }

    @Test func moveUpShiftsCursorIndex() {
        var queue = Queue(tracks: [makeTrack("a"), makeTrack("b"), makeTrack("c")])
        queue.jump(to: 2)

        queue.move(from: 2, to: 0)

        #expect(queue.tracks.map(\.id) == ["c", "a", "b"])
        #expect(queue.current?.id == "c")
    }

    @Test func moveIgnoresInvalidIndices() {
        var queue = Queue(tracks: [makeTrack("a")])
        queue.move(from: 5, to: 0)
        queue.move(from: 0, to: 9)
        #expect(queue.tracks.map(\.id) == ["a"])
    }
}
