// RecommendationTests.swift: signals, decay, shrinkage, ranking, diversity,
// cold start, feedback, refresh policy and the seeded benchmark.
import Foundation
import Testing
@testable import MonochromeCore

private func track(
    _ id: String,
    title: String? = nil,
    artist: String,
    album: String = "",
    duration: Double = 200
) -> Track {
    Track(
        id: Track.remoteIDPrefix + id,
        title: title ?? "Song \(id)",
        artist: artist,
        album: album,
        durationSeconds: duration,
        provider: "monochrome",
        streamID: id
    )
}

private func completedEvent(
    _ id: String,
    artist: String,
    album: String = "",
    daysAgo: Double = 0,
    listened: Double = 200,
    duration: Double = 200,
    loop: Bool = false
) -> PlayEvent {
    PlayEvent(
        source: "monochrome",
        trackID: Track.remoteIDPrefix + id,
        artist: artist,
        album: album,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000 - daysAgo * 86_400),
        listenedSeconds: listened,
        duration: duration,
        outcome: .completed,
        loop: loop
    )
}

@Suite("Taste profile")
struct TasteProfileTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("a completed track scales with the listened fraction")
    func completedFraction() {
        let half = completedEvent("a", artist: "Artist", listened: 100, duration: 200)
        let profile = TasteProfile.build(events: [half], now: now)
        // Raw affinity is 0.5, shrunk by A / (A + 3).
        let expected = 0.5 / (0.5 + 3)
        #expect(abs(profile.artistScore("Artist") - expected) < 0.0001)
    }

    @Test("favourites and downloads weigh more than a play")
    func signalWeights() {
        var events = [completedEvent("a", artist: "Artist")]
        events.append(PlayEvent(
            source: "monochrome", trackID: "b", artist: "Artist", album: "",
            startedAt: now, outcome: .favorited))
        events.append(PlayEvent(
            source: "monochrome", trackID: "c", artist: "Artist", album: "",
            startedAt: now, outcome: .downloaded))
        let profile = TasteProfile.build(events: events, now: now)
        let raw = 1.0 + 3.0 + 2.0
        #expect(abs(profile.artistScore("Artist") - raw / (raw + 3)) < 0.0001)
    }

    @Test("a loop adds a small bonus")
    func loopBonus() {
        let plain = TasteProfile.build(events: [completedEvent("a", artist: "Artist")], now: now)
        let looped = TasteProfile.build(
            events: [completedEvent("a", artist: "Artist", loop: true)],
            now: now
        )
        #expect(looped.artistScore("Artist") > plain.artistScore("Artist"))
    }

    @Test("only early skips count against the taste")
    func skipRules() {
        let early = completedEvent("a", artist: "Artist", listened: 10, duration: 200)
        let skippedEarly = PlayEvent(
            source: "monochrome", trackID: "a", artist: "Artist", album: "",
            startedAt: now, listenedSeconds: 10, duration: 200, outcome: .skipped)
        let skippedLate = PlayEvent(
            source: "monochrome", trackID: "a", artist: "Artist", album: "",
            startedAt: now, listenedSeconds: 180, duration: 200, outcome: .skipped)

        let earlyProfile = TasteProfile.build(events: [skippedEarly], now: now)
        let lateProfile = TasteProfile.build(events: [skippedLate], now: now)
        #expect(earlyProfile.artistScore("Artist") < 0)
        #expect(lateProfile.artistScore("Artist") == 0)
        #expect(TasteProfile.build(events: [early], now: now).artistScore("Artist") > 0)
    }

    @Test("time decay halves the weight after 45 days")
    func decay() {
        let fresh = TasteProfile.build(events: [completedEvent("a", artist: "Artist")], now: now)
        let old = TasteProfile.build(
            events: [completedEvent("a", artist: "Artist", daysAgo: 45)],
            now: now
        )
        let expected = 0.5 / (0.5 + 3)
        #expect(abs(old.artistScore("Artist") - expected) < 0.0001)
        #expect(fresh.artistScore("Artist") > old.artistScore("Artist"))
    }

    @Test("not for me punishes the track and the artist")
    func negativeFeedback() {
        let event = PlayEvent(
            source: "monochrome", trackID: Track.remoteIDPrefix + "a", artist: "Artist", album: "Album",
            startedAt: now, outcome: .notForMe)
        let profile = TasteProfile.build(events: [event], now: now)
        #expect(profile.trackScore("monochrome|\(Track.remoteIDPrefix)a") < 0)
        #expect(profile.artistScore("Artist") < 0)
    }

    @Test("cold start needs twenty events")
    func coldStart() {
        var events: [PlayEvent] = []
        for index in 0..<19 {
            events.append(completedEvent("\(index)", artist: "Artist"))
        }
        #expect(TasteProfile.build(events: events, now: now).isColdStart)
        events.append(completedEvent("19", artist: "Artist"))
        #expect(TasteProfile.build(events: events, now: now).isColdStart == false)
    }
}

@Suite("Recommendation ranking")
struct RecommendationRankingTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func profile(events: [PlayEvent]) -> TasteProfile {
        TasteProfile.build(events: events, now: now)
    }

    @Test("the liked artist ranks first and carries the reason")
    func rankingAndReason() {
        let profile = profile(events: (0..<10).map { completedEvent("\($0)", artist: "Loved") })
        let candidates = [
            track("x", artist: "Loved", album: "Album"),
            track("y", artist: "Other", album: "Other Album"),
        ]
        let ranked = RecommendationRanker.rank(candidates: candidates, profile: profile)
        #expect(ranked.first?.track.id == Track.remoteIDPrefix + "x")
        #expect(ranked.first?.reason == "Because you play Loved")
    }

    @Test("no artist takes more than two slots in the first ten")
    func diversity() {
        let artists = ["One", "Two", "Three", "Four", "Five"]
        var events: [PlayEvent] = []
        for artist in artists {
            events.append(contentsOf: (0..<10).map { completedEvent("\(artist)\($0)", artist: artist) })
        }
        let profile = profile(events: events)
        var candidates: [Track] = []
        for artist in artists {
            candidates.append(contentsOf: (0..<4).map { track("\(artist)\($0)", artist: artist) })
        }
        let ranked = RecommendationRanker.rank(candidates: candidates, profile: profile, limit: 20)
        for artist in artists {
            let inTop = ranked.prefix(10).filter { $0.track.artist == artist }.count
            #expect(inTop <= RecommendationRanker.diversityLimit)
        }
        #expect(ranked.prefix(10).count == 10)
    }

    @Test("a pool with few artists still fills the list")
    func diversityFallback() {
        var events = (0..<10).map { completedEvent("loved\($0)", artist: "Loved") }
        events += (0..<10).map { completedEvent("other\($0)", artist: "Other") }
        let profile = profile(events: events)
        let candidates = (0..<8).map { track("loved\($0)", artist: "Loved") }
            + (0..<8).map { track("other\($0)", artist: "Other") }
        let ranked = RecommendationRanker.rank(candidates: candidates, profile: profile, limit: 10)
        #expect(ranked.count == 10)
    }

    @Test("a track the listener dislikes is not recommended")
    func negativeAffinity() {
        var events = (0..<10).map { completedEvent("\($0)", artist: "Loved") }
        events.append(PlayEvent(
            source: "monochrome", trackID: Track.remoteIDPrefix + "hated", artist: "Loved", album: "Album",
            startedAt: now, outcome: .notForMe))
        let profile = profile(events: events)
        let candidates = [track("hated", artist: "Loved", album: "Album"), track("ok", artist: "Loved")]
        let ranked = RecommendationRanker.rank(candidates: candidates, profile: profile)
        #expect(ranked.first?.track.id == Track.remoteIDPrefix + "ok")
    }

    @Test("repeated plays lower the score a little")
    func repeatPenalty() {
        let once = profile(events: [completedEvent("a", artist: "Loved")])
        let many = profile(events: (0..<5).map { _ in completedEvent("a", artist: "Loved") })
        let candidate = track("a", artist: "Loved")
        let single = RecommendationRanker.rank(candidates: [candidate], profile: once)
        let repeated = RecommendationRanker.rank(candidates: [candidate], profile: many)
        #expect(single.isEmpty == false)
        #expect(repeated.isEmpty == false)
        #expect(single.first!.score > repeated.first!.score)
    }
}

@MainActor
@Suite("Recommendation engine")
struct RecommendationEngineTests {
    private func temporaryStore() -> PlayEventStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("events-\(UUID().uuidString).json")
        return PlayEventStore(fileURL: url)
    }

    @Test("events are stored, capped and reloaded")
    func storeRoundTrip() throws {
        let store = temporaryStore()
        var content = PlayEventStore.Content()
        for index in 0..<10 {
            content.events.append(PlayEvent(
                source: "monochrome", trackID: "\(index)", artist: "Artist", album: "",
                startedAt: .now, outcome: .completed))
        }
        try store.save(content)
        #expect(store.load().events.count == 10)
        #expect(store.load().schemaVersion == PlayEventStore.schemaVersion)
    }

    @Test("the engine stays empty while the taste is cold")
    func coldStartEngine() async {
        let engine = RecommendationEngine(store: temporaryStore(), search: { _ in [] })
        engine.record(PlayEvent(
            source: "monochrome", trackID: "a", artist: "Artist", album: "",
            startedAt: .now, outcome: .completed))
        #expect(engine.isColdStart)
        await engine.refresh()
        #expect(engine.recommendations.isEmpty)
    }

    @Test("refresh asks for candidates and ranks them")
    func refreshRanks() async {
        let engine = RecommendationEngine(store: temporaryStore(), search: { query in
            [track("1", artist: query, album: "Album")]
        })
        for index in 0..<25 {
            engine.record(PlayEvent(
                source: "monochrome", trackID: "\(index)", artist: "Loved", album: "Album",
                startedAt: .now, listenedSeconds: 200, duration: 200, outcome: .completed))
        }
        await engine.refresh()
        #expect(!engine.recommendations.isEmpty)
        #expect(engine.recommendations.first?.reason.contains("Loved") == true)
    }

    @Test("a second refresh inside the interval makes no request")
    func refreshPolicy() async {
        let counter = Counter()
        let engine = RecommendationEngine(store: temporaryStore(), search: { query in
            counter.increment()
            return [track("1", artist: query)]
        })
        for index in 0..<25 {
            engine.record(PlayEvent(
                source: "monochrome", trackID: "\(index)", artist: "Loved", album: "",
                startedAt: .now, listenedSeconds: 200, duration: 200, outcome: .completed))
        }
        await engine.refresh()
        let afterFirst = counter.count
        await engine.refresh()
        #expect(counter.count == afterFirst)
        #expect(afterFirst <= RecommendationEngine.maxRequestsPerRefresh)
    }

    @Test("feedback changes the profile and reset clears it")
    func feedbackAndReset() {
        let engine = RecommendationEngine(store: temporaryStore())
        let track = track("1", artist: "Artist", album: "Album")
        engine.moreLikeThis(track)
        #expect(engine.profile.artistScore("Artist") > 0)
        engine.notForMe(track)
        #expect(engine.profile.trackScore(track.sourceKey) < 0)
        engine.reset()
        #expect(engine.events.isEmpty)
        #expect(engine.profile.eventCount == 0)
    }

    @Test("bootstrapping happens once")
    func bootstrapOnce() {
        let engine = RecommendationEngine(store: temporaryStore())
        let favorites = [track("f", artist: "Fav")]
        engine.bootstrapOnce(favorites: favorites, recents: [track("r", artist: "Recent")])
        let count = engine.eventCount
        engine.bootstrapOnce(favorites: favorites, recents: [])
        #expect(engine.eventCount == count)
    }
}

/// Thread-safe counter for request assertions.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

@Suite("Recommendation benchmark")
struct RecommendationBenchmarkTests {
    /// A seeded synthetic listener: two loved artists and a set of tracks that
    /// are heard often but always skipped. The shelf has to find the
    /// unfamiliar tracks by the loved artists and beat the "most heard" and
    /// "most recent" baselines.
    @Test("the familiar shelf is precise and beats the baselines")
    func benchmark() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let loved = ["Alpha", "Beta", "Gamma", "Delta", "Epsilon"]
        var events: [PlayEvent] = []

        // Five loved artists, six plays each, ten days ago.
        for (artistIndex, artist) in loved.enumerated() {
            for index in 0..<6 {
                events.append(PlayEvent(
                    source: "monochrome", trackID: "old\(artistIndex)\(index)",
                    artist: artist, album: "\(artist) Album",
                    startedAt: now.addingTimeInterval(Double(index) * 3600 - 10 * 86_400),
                    listenedSeconds: 200, duration: 200, outcome: .completed))
            }
        }

        // Thirty candidates that keep coming back and are always skipped.
        var noise: [Track] = []
        for index in 0..<30 {
            let track = track("noise\(index)", artist: "Noise \(index % 7)", album: "Other")
            noise.append(track)
            events.append(PlayEvent(
                source: "monochrome", trackID: track.id, artist: track.artist, album: track.album,
                startedAt: now.addingTimeInterval(Double(index) * 60 - 3600),
                listenedSeconds: 8, duration: 200, outcome: .skipped))
        }

        // The pool: ten new tracks by the loved artists and the thirty noise
        // tracks.
        var candidates: [Track] = []
        var familiarKeys: Set<String> = []
        for (artistIndex, artist) in loved.enumerated() {
            for index in 0..<2 {
                let familiar = track(
                    "familiar\(artistIndex)\(index)",
                    artist: artist,
                    album: "\(artist) Album"
                )
                familiarKeys.insert(familiar.sourceKey)
                candidates.append(familiar)
            }
        }
        candidates.append(contentsOf: noise)

        let profile = TasteProfile.build(events: events, now: now)
        let ranked = RecommendationRanker.rank(candidates: candidates, profile: profile, limit: 10)
        let hits = ranked.filter { familiarKeys.contains($0.track.sourceKey) }.count
        let precision = Double(hits) / Double(max(ranked.count, 1))
        #expect(precision >= 0.90, "precision@10 was \(precision)")
        #expect(ranked.count == 10)

        // Popularity baseline: the candidate tracks heard most often.
        let heardCounts = Dictionary(grouping: events, by: \.trackKey).mapValues(\.count)
        let byPopularity = candidates.sorted {
            (heardCounts[$0.sourceKey] ?? 0) > (heardCounts[$1.sourceKey] ?? 0)
        }
        let popularityHits = byPopularity.prefix(10)
            .filter { familiarKeys.contains($0.sourceKey) }.count

        // Recency baseline: the candidate tracks heard most recently.
        let lastHeard = Dictionary(grouping: events, by: \.trackKey)
            .mapValues { $0.map(\.startedAt).max() ?? .distantPast }
        let byRecency = candidates.sorted {
            (lastHeard[$0.sourceKey] ?? .distantPast) > (lastHeard[$1.sourceKey] ?? .distantPast)
        }
        let recencyHits = byRecency.prefix(10)
            .filter { familiarKeys.contains($0.sourceKey) }.count

        #expect(hits > popularityHits)
        #expect(hits > recencyHits)
    }
}
