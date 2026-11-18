// SearchQueryStateTests.swift: the search reducer and skeleton timing.
import Foundation
import Testing
@testable import MonochromeCore

private func payload(_ title: String = "a") -> SearchPayload {
    SearchPayload(tracks: [Track(id: "1", title: title)])
}

@Suite("Search query state")
struct SearchQueryStateTests {
    @Test("a short query stays idle and no results are claimed")
    func shortQuery() {
        var state = SearchQueryState()
        state.queryChanged(" ")
        #expect(state.phase == .idle)
        state.queryChanged("n")
        #expect(state.phase == .idle)
        #expect(state.activeQuery == nil)
        #expect(!state.showsNoResults)
    }

    @Test("typing waits, then loading, then results")
    func happyPath() {
        var state = SearchQueryState()
        state.queryChanged("neon")
        #expect(state.phase == .typing("neon"))
        #expect(state.isWaiting)
        #expect(!state.showsNoResults)

        state.requestStarted(for: "neon")
        #expect(state.phase == .loading("neon"))

        state.received(payload(), for: "neon")
        #expect(state.payload?.tracks.count == 1)
        #expect(state.resultsQuery == "neon")
        #expect(!state.isWaiting)
        #expect(!state.showsNoResults)
    }

    @Test("an empty answer is the only way to show no results")
    func emptyAnswer() {
        var state = SearchQueryState()
        state.queryChanged("zzzz")
        state.requestStarted(for: "zzzz")
        state.received(SearchPayload(), for: "zzzz")
        #expect(state.showsNoResults)
        #expect(state.failureMessage == nil)
    }

    @Test("a failure is an error, never an empty answer")
    func failure() {
        var state = SearchQueryState()
        state.queryChanged("neon")
        state.requestStarted(for: "neon")
        state.failed("The request timed out.", for: "neon")
        #expect(!state.showsNoResults)
        #expect(state.failureMessage == "The request timed out.")
    }

    @Test("an answer for a stale query is dropped")
    func staleAnswer() {
        var state = SearchQueryState()
        state.queryChanged("neon")
        state.requestStarted(for: "neon")
        state.queryChanged("neon moon")
        #expect(state.phase == .typing("neon moon"))

        // The slow first request answers after the query moved on.
        state.received(payload("late"), for: "neon")
        #expect(state.phase == .typing("neon moon"))
        #expect(state.payload == nil)

        state.requestStarted(for: "neon moon")
        state.received(payload("right"), for: "neon moon")
        #expect(state.payload?.tracks.first?.title == "right")
    }

    @Test("a stale request start cannot move a newer query to loading")
    func staleStart() {
        var state = SearchQueryState()
        state.queryChanged("first")
        state.queryChanged("second")
        state.requestStarted(for: "first")
        #expect(state.phase == .typing("second"))
    }

    @Test("clearing the field returns to idle")
    func cleared() {
        var state = SearchQueryState()
        state.queryChanged("neon")
        state.requestStarted(for: "neon")
        state.received(payload(), for: "neon")
        state.queryChanged("")
        #expect(state.phase == .idle)
        #expect(state.payload == nil)
        #expect(state.activeQuery == nil)
    }

    @Test("the last answer stays while the next query loads")
    func keepsLastAnswer() {
        var state = SearchQueryState()
        state.queryChanged("neon")
        state.requestStarted(for: "neon")
        state.received(payload("old"), for: "neon")

        state.queryChanged("neon moon")
        #expect(state.shownPayload.tracks.first?.title == "old")
        #expect(state.payload == nil)

        state.requestStarted(for: "neon moon")
        #expect(state.shownPayload.tracks.first?.title == "old")

        state.received(payload("new"), for: "neon moon")
        #expect(state.shownPayload.tracks.first?.title == "new")
    }

    @Test("an empty answer or a cleared field drops the last answer")
    func dropsLastAnswer() {
        var state = SearchQueryState()
        state.queryChanged("neon")
        state.requestStarted(for: "neon")
        state.received(SearchPayload(), for: "neon")
        state.queryChanged("zzzz")
        #expect(state.shownPayload.isEmpty)

        var cleared = SearchQueryState()
        cleared.queryChanged("neon")
        cleared.requestStarted(for: "neon")
        cleared.received(SearchPayload(), for: "neon")
        cleared.queryChanged("")
        #expect(cleared.shownPayload.isEmpty)
    }

    @Test("the same query typed again keeps its phase")
    func sameQuery() {
        var state = SearchQueryState()
        state.queryChanged("neon")
        state.requestStarted(for: "neon")
        state.received(payload(), for: "neon")
        state.queryChanged("neon")
        #expect(state.resultsQuery == "neon")
    }
}

@Suite("Search skeleton timing")
struct SearchSkeletonTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private func at(_ ms: Double) -> Date { start.addingTimeInterval(ms / 1000) }

    @Test("a fast answer never shows the skeleton")
    func fastAnswer() {
        var skeleton = SearchSkeletonState()
        skeleton.update(waiting: true, at: start)
        #expect(!skeleton.isVisible)
        skeleton.update(waiting: false, at: at(100))
        #expect(!skeleton.isVisible)
    }

    @Test("the skeleton appears after the grace period")
    func grace() {
        var skeleton = SearchSkeletonState()
        skeleton.update(waiting: true, at: start)
        skeleton.update(waiting: true, at: at(149))
        #expect(!skeleton.isVisible)
        skeleton.update(waiting: true, at: at(150))
        #expect(skeleton.isVisible)
    }

    @Test("a shown skeleton stays for the minimum")
    func minimumVisible() {
        var skeleton = SearchSkeletonState()
        skeleton.update(waiting: true, at: start)
        skeleton.update(waiting: true, at: at(160))
        #expect(skeleton.isVisible)

        skeleton.update(waiting: false, at: at(200))
        #expect(skeleton.isVisible)
        skeleton.update(waiting: false, at: at(459))
        #expect(skeleton.isVisible)
        skeleton.update(waiting: false, at: at(460))
        #expect(!skeleton.isVisible)
    }

    @Test("the next change delay points at the grace or the minimum")
    func delays() {
        var skeleton = SearchSkeletonState()
        skeleton.update(waiting: true, at: start)
        #expect(skeleton.nextChangeDelay(at: start) == 0.15)

        skeleton.update(waiting: true, at: at(150))
        #expect(skeleton.isVisible)
        #expect(skeleton.nextChangeDelay(at: at(150)) == nil)

        skeleton.update(waiting: false, at: at(200))
        let delay = skeleton.nextChangeDelay(at: at(200)) ?? 0
        #expect(abs(delay - 0.25) < 0.001)
    }

    @Test("a long wait keeps the skeleton up")
    func longWait() {
        var skeleton = SearchSkeletonState()
        skeleton.update(waiting: true, at: start)
        skeleton.update(waiting: true, at: at(150))
        skeleton.update(waiting: true, at: at(9_000))
        #expect(skeleton.isVisible)
        #expect(skeleton.nextChangeDelay(at: at(9_000)) == nil)
    }
}
