// QuickAccessTests.swift: ordering, de-duplication and the tile limit.
import Testing
@testable import MonochromeCore

@Suite("QuickAccess")
struct QuickAccessTests {
    private func track(_ id: String) -> Track {
        Track(id: id, title: id)
    }

    @Test func recentsComeFirstAndDuplicatesAreDropped() {
        let merged = QuickAccess.merge(
            recents: [track("a"), track("b")],
            favorites: [track("b"), track("c")]
        )
        #expect(merged.map(\.id) == ["a", "b", "c"])
    }

    @Test func limitIsAppliedAfterMerging() {
        let merged = QuickAccess.merge(
            recents: [track("a"), track("b")],
            favorites: [track("c"), track("d")],
            limit: 3
        )
        #expect(merged.map(\.id) == ["a", "b", "c"])
    }

    @Test func emptyInputsStayEmpty() {
        #expect(QuickAccess.merge(recents: [], favorites: []).isEmpty)
    }

    @Test func nonPositiveLimitReturnsEmpty() {
        #expect(QuickAccess.merge(recents: [track("a")], favorites: [], limit: 0).isEmpty)
    }
}
