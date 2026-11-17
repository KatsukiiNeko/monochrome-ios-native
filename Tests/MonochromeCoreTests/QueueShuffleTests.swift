// QueueShuffleTests.swift: determinism, pinned current and queue commands.
import Foundation
import Testing
@testable import MonochromeCore

private func track(_ id: String) -> Track {
    Track(id: id, title: "Track \(id)")
}

@Suite("QueueShuffle")
struct QueueShuffleTests {
    private let ids = ["a", "b", "c", "d", "e"]

    private func tracks() -> [Track] { ids.map(track) }

    @Test("a pinned track stays put and no entry is lost")
    func pinnedShuffle() {
        let first = QueueShuffle.shuffled(tracks(), pinIndex: 2, generator: seededGenerator(seed: 7))
        let second = QueueShuffle.shuffled(tracks(), pinIndex: 2, generator: seededGenerator(seed: 7))
        #expect(first.map(\.id) == second.map(\.id))
        #expect(first[2].id == "c")
        #expect(Set(first.map(\.id)) == Set(ids))
        #expect(first != tracks(), "a seeded shuffle must not return the input order")
    }

    @Test("empty and single-item queues are untouched")
    func edges() {
        #expect(QueueShuffle.shuffled([Track](), pinIndex: nil, generator: { _ in 0 }).isEmpty)
        let single = QueueShuffle.shuffled([track("a")], pinIndex: 0, generator: { _ in 0 })
        #expect(single.map(\.id) == ["a"])
        // A pin outside the range shuffles everything instead.
        let all = QueueShuffle.shuffled(tracks(), pinIndex: 9, generator: seededGenerator(seed: 3))
        #expect(Set(all.map(\.id)) == Set(ids))
    }
}
