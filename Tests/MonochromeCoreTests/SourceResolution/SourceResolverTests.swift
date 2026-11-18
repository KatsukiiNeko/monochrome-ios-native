// SourceResolverTests.swift: link lifetime, caching and the search budget.
import Foundation
import Testing
@testable import MonochromeCore

private let day: TimeInterval = 86_400
private let start = Date(timeIntervalSince1970: 1_700_000_000)

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date = start) { self.value = value }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(_ interval: TimeInterval) {
        lock.lock()
        value.addTimeInterval(interval)
        lock.unlock()
    }
}

private enum FakeFailure: Error {
    case offline
}

private final class FakeSource: SourceSearching, @unchecked Sendable {
    private let lock = NSLock()
    private var queries: [String] = []
    private var results: [Track]
    private var delay: Duration?
    private var failure: (any Error)?

    init(_ results: [Track] = []) {
        self.results = results
    }

    func set(results: [Track]) {
        lock.lock()
        self.results = results
        lock.unlock()
    }

    func set(delay: Duration?) {
        lock.lock()
        self.delay = delay
        lock.unlock()
    }

    func fail(_ error: any Error) {
        lock.lock()
        failure = error
        lock.unlock()
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return queries.count
    }

    var lastQuery: String? {
        lock.lock()
        defer { lock.unlock() }
        return queries.last
    }

    private func take(for query: String) -> ([Track], Duration?, (any Error)?) {
        lock.lock()
        defer { lock.unlock() }
        queries.append(query)
        return (results, delay, failure)
    }

    func searchTracks(matching query: String, limit: Int) async throws -> [Track] {
        let (results, delay, failure) = take(for: query)
        if let delay { try? await Task.sleep(for: delay) }
        if let failure { throw failure }
        return results
    }
}

private func track(
    _ title: String,
    by artist: String,
    provider: MusicSourceID,
    seconds: Double? = 200,
    isrc: String? = nil
) -> Track {
    Track(
        id: "\(provider.rawValue):\(title)|\(artist)",
        title: title,
        artist: artist,
        album: "Harbour Lights",
        durationSeconds: seconds,
        provider: provider.rawValue,
        streamID: "id-\(title)",
        isrc: isrc
    )
}

private let companionTrack = track("Neon Harbour", by: "Aster Vale", provider: .youTubeMusic)
private let hifiTrack = track("Neon Harbour", by: "Aster Vale", provider: .monochrome)

private func makeStore(_ clock: TestClock, fileURL: URL? = nil) -> SourceLinkStore {
    let url = fileURL ?? FileManager.default.temporaryDirectory
        .appendingPathComponent("source-links-\(UUID().uuidString).json")
    return SourceLinkStore(fileURL: url, now: { clock.now })
}

private func makeResolver(
    hifi: FakeSource,
    companion: FakeSource,
    store: SourceLinkStore,
    clock: TestClock,
    budget: Duration = .seconds(5)
) -> SourceResolver {
    SourceResolver(
        hifi: hifi,
        companion: companion,
        store: store,
        budget: budget,
        now: { clock.now }
    )
}

private func confirmedLink(
    from provider: MusicSourceID,
    _ source: Track,
    counterpart: Track,
    at date: Date = start
) -> SourceLink {
    SourceLink(
        provider: provider.rawValue,
        trackID: source.id,
        counterpartProvider: counterpart.provider,
        counterpart: counterpart,
        state: .confirmed,
        method: .heuristic,
        confidence: 0.95,
        updatedAt: date
    )
}

@Suite("Source link lifetime")
struct SourceLinkLifetimeTests {
    @Test("a confirmed link lives thirty days")
    func confirmedLifetime() {
        let clock = TestClock()
        let store = makeStore(clock)
        try? store.record(confirmedLink(from: .youTubeMusic, companionTrack, counterpart: hifiTrack))

        clock.advance(29 * day)
        #expect(store.link(provider: companionTrack.provider, trackID: companionTrack.id, counterpartProvider: "monochrome") != nil)

        clock.advance(2 * day)
        #expect(store.link(provider: companionTrack.provider, trackID: companionTrack.id, counterpartProvider: "monochrome") == nil)
    }

    @Test("a rejection is retried after a day")
    func rejectedLifetime() {
        let clock = TestClock()
        let store = makeStore(clock)
        try? store.record(
            SourceLink(
                provider: companionTrack.provider,
                trackID: companionTrack.id,
                counterpartProvider: "monochrome",
                counterpart: nil,
                state: .rejected,
                method: .heuristic,
                confidence: 0,
                updatedAt: clock.now
            )
        )

        clock.advance(23 * 3_600)
        #expect(store.link(provider: companionTrack.provider, trackID: companionTrack.id, counterpartProvider: "monochrome") != nil)

        clock.advance(2 * 3_600)
        #expect(store.link(provider: companionTrack.provider, trackID: companionTrack.id, counterpartProvider: "monochrome") == nil)
    }

    @Test("a manual verdict never expires on its own")
    func manualLifetime() {
        let clock = TestClock()
        let store = makeStore(clock)
        try? store.record(
            SourceLink(
                provider: companionTrack.provider,
                trackID: companionTrack.id,
                counterpartProvider: "monochrome",
                counterpart: nil,
                state: .manual,
                method: .heuristic,
                confidence: 0,
                updatedAt: clock.now
            )
        )

        clock.advance(5 * 365 * day)
        #expect(store.link(provider: companionTrack.provider, trackID: companionTrack.id, counterpartProvider: "monochrome")?.state == .manual)
    }

    @Test("the cap keeps the newest links")
    func capKeepsNewest() {
        let links = (0..<5_100).map { index in
            SourceLink(
                provider: "youTubeMusic",
                trackID: "track-\(index)",
                counterpartProvider: "monochrome",
                counterpart: hifiTrack,
                state: .confirmed,
                method: .heuristic,
                confidence: 0.95,
                updatedAt: start.addingTimeInterval(Double(index))
            )
        }
        let trimmed = SourceLinkStore.trim(links, at: start.addingTimeInterval(10_000))
        #expect(trimmed.count == SourceLinkStore.maxLinks)
        #expect(trimmed.contains { $0.trackID == "track-5099" })
        #expect(!trimmed.contains { $0.trackID == "track-0" })
    }

    @Test("links survive a new store instance on the same file")
    func persists() {
        let clock = TestClock()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("source-links-\(UUID().uuidString).json")
        try? makeStore(clock, fileURL: url)
            .record(confirmedLink(from: .youTubeMusic, companionTrack, counterpart: hifiTrack))

        let reopened = makeStore(clock, fileURL: url)
        let link = reopened.link(
            provider: companionTrack.provider,
            trackID: companionTrack.id,
            counterpartProvider: "monochrome"
        )
        #expect(link?.counterpart?.id == hifiTrack.id)
    }
}

@Suite("Source resolution")
struct SourceResolutionTests {
    @Test("a companion track resolves to its HiFi copy and is cached")
    func losslessSubstitution() async {
        let clock = TestClock()
        let store = makeStore(clock)
        let hifi = FakeSource([hifiTrack])
        let companion = FakeSource([])
        let resolver = makeResolver(hifi: hifi, companion: companion, store: store, clock: clock)

        let first = await resolver.losslessCounterpart(for: companionTrack)
        #expect(first?.id == hifiTrack.id)
        #expect(hifi.callCount == 1)
        #expect(hifi.lastQuery == "Neon Harbour Aster Vale")

        let second = await resolver.losslessCounterpart(for: companionTrack)
        #expect(second?.id == hifiTrack.id)
        #expect(hifi.callCount == 1)
    }

    @Test("a wrong recording is not chosen")
    func noWrongVersion() async {
        let clock = TestClock()
        let store = makeStore(clock)
        let live = track("Neon Harbour (Live)", by: "Aster Vale", provider: .monochrome)
        let resolver = makeResolver(
            hifi: FakeSource([live]),
            companion: FakeSource([]),
            store: store,
            clock: clock
        )

        #expect(await resolver.losslessCounterpart(for: companionTrack) == nil)
    }

    @Test("a rejection is remembered for a day and then searched again")
    func rejectionCache() async {
        let clock = TestClock()
        let store = makeStore(clock)
        let hifi = FakeSource([])
        let resolver = makeResolver(hifi: hifi, companion: FakeSource([]), store: store, clock: clock)

        #expect(await resolver.losslessCounterpart(for: companionTrack) == nil)
        #expect(hifi.callCount == 1)

        clock.advance(2 * 3_600)
        #expect(await resolver.losslessCounterpart(for: companionTrack) == nil)
        #expect(hifi.callCount == 1)

        hifi.set(results: [hifiTrack])
        clock.advance(25 * 3_600)
        #expect(await resolver.losslessCounterpart(for: companionTrack)?.id == hifiTrack.id)
        #expect(hifi.callCount == 2)
    }

    @Test("a slow search is abandoned and leaves no verdict")
    func searchBudget() async {
        let clock = TestClock()
        let store = makeStore(clock)
        let hifi = FakeSource([hifiTrack])
        hifi.set(delay: .milliseconds(300))
        let resolver = makeResolver(
            hifi: hifi,
            companion: FakeSource([]),
            store: store,
            clock: clock,
            budget: .milliseconds(20)
        )

        #expect(await resolver.losslessCounterpart(for: companionTrack) == nil)
        #expect(store.link(provider: companionTrack.provider, trackID: companionTrack.id, counterpartProvider: "monochrome") == nil)

        hifi.set(delay: nil)
        #expect(await resolver.losslessCounterpart(for: companionTrack)?.id == hifiTrack.id)
        #expect(hifi.callCount == 2)
    }

    @Test("a failed search leaves no verdict")
    func searchFailure() async {
        let clock = TestClock()
        let store = makeStore(clock)
        let hifi = FakeSource([hifiTrack])
        hifi.fail(FakeFailure.offline)
        let resolver = makeResolver(hifi: hifi, companion: FakeSource([]), store: store, clock: clock)

        #expect(await resolver.losslessCounterpart(for: companionTrack) == nil)
        #expect(store.link(provider: companionTrack.provider, trackID: companionTrack.id, counterpartProvider: "monochrome") == nil)
    }

    @Test("a cancelled play stops waiting and leaves no verdict")
    func cancellation() async {
        let clock = TestClock()
        let store = makeStore(clock)
        let hifi = FakeSource([hifiTrack])
        hifi.set(delay: .milliseconds(300))
        let resolver = makeResolver(
            hifi: hifi,
            companion: FakeSource([]),
            store: store,
            clock: clock,
            budget: .seconds(5)
        )

        let task = Task { await resolver.losslessCounterpart(for: companionTrack) }
        try? await Task.sleep(for: .milliseconds(20))
        task.cancel()
        #expect(await task.value == nil)
        #expect(store.link(provider: companionTrack.provider, trackID: companionTrack.id, counterpartProvider: "monochrome") == nil)
    }

    @Test("the listener can overrule a substitution until they clear it")
    func manualOverride() async {
        let clock = TestClock()
        let store = makeStore(clock)
        let hifi = FakeSource([hifiTrack])
        let resolver = makeResolver(hifi: hifi, companion: FakeSource([]), store: store, clock: clock)

        #expect(await resolver.losslessCounterpart(for: companionTrack)?.id == hifiTrack.id)
        resolver.useOriginal(for: companionTrack, counterpartProvider: .monochrome)
        #expect(await resolver.losslessCounterpart(for: companionTrack) == nil)
        #expect(hifi.callCount == 1)

        resolver.clearVerdict(for: companionTrack, counterpartProvider: .monochrome)
        #expect(await resolver.losslessCounterpart(for: companionTrack)?.id == hifiTrack.id)
        #expect(hifi.callCount == 2)
    }

    @Test("the companion copy is found for a HiFi track")
    func companionFallback() async {
        let clock = TestClock()
        let store = makeStore(clock)
        let companion = FakeSource([companionTrack])
        let resolver = makeResolver(
            hifi: FakeSource([]),
            companion: companion,
            store: store,
            clock: clock
        )

        #expect(await resolver.companionCounterpart(for: hifiTrack)?.id == companionTrack.id)
        #expect(store.link(provider: hifiTrack.provider, trackID: hifiTrack.id, counterpartProvider: "youTubeMusic")?.counterpart != nil)
    }

    @Test("only the two music sources take part")
    func directionGuards() async {
        let clock = TestClock()
        let store = makeStore(clock)
        let hifi = FakeSource([hifiTrack])
        let companion = FakeSource([companionTrack])
        let resolver = makeResolver(hifi: hifi, companion: companion, store: store, clock: clock)
        let episode = track("Episode 7", by: "A Show", provider: .podcast)

        #expect(await resolver.losslessCounterpart(for: hifiTrack) == nil)
        #expect(await resolver.companionCounterpart(for: companionTrack) == nil)
        #expect(await resolver.losslessCounterpart(for: episode) == nil)
        #expect(await resolver.companionCounterpart(for: episode) == nil)
        #expect(hifi.callCount == 0)
        #expect(companion.callCount == 0)
    }

    @Test("the canonical key follows the linked copy")
    func canonicalKey() {
        let clock = TestClock()
        let store = makeStore(clock)
        let resolver = makeResolver(hifi: FakeSource(), companion: FakeSource(), store: store, clock: clock)

        #expect(resolver.canonicalKey(for: companionTrack) == companionTrack.sourceKey)
        try? store.record(confirmedLink(from: .youTubeMusic, companionTrack, counterpart: hifiTrack))
        #expect(resolver.canonicalKey(for: companionTrack) == hifiTrack.sourceKey)
    }

    @Test("an equal ISRC wins before the text is compared")
    func isrcWins() async {
        let clock = TestClock()
        let store = makeStore(clock)
        let reference = track("Neon Harbour", by: "Aster Vale", provider: .monochrome, isrc: "USAAA2400001")
        let candidate = track("Different Words", by: "Other Artist", provider: .youTubeMusic, isrc: "US-AAA-24-00001")
        let resolver = makeResolver(
            hifi: FakeSource([]),
            companion: FakeSource([candidate]),
            store: store,
            clock: clock
        )

        #expect(await resolver.companionCounterpart(for: reference)?.id == candidate.id)
        #expect(
            store.link(
                provider: reference.provider,
                trackID: reference.id,
                counterpartProvider: "youTubeMusic"
            )?.method == .isrc
        )
    }
}
