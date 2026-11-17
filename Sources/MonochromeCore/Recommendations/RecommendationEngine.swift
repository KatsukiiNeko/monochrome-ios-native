// RecommendationEngine.swift: the on-device recommendation model. It keeps the
// event log, turns it into a taste profile and refreshes candidates at most
// every six hours with at most six searches.
import Foundation
import Observation

/// Candidate sources for one refresh.
public typealias RecommendationSearch = @Sendable (String) async throws -> [Track]

@MainActor
@Observable
public final class RecommendationEngine {
    /// Refresh the candidate list at most this often.
    public static let refreshInterval: TimeInterval = 6 * 3600
    /// Candidates stay usable for a day.
    public static let candidateLifetime: TimeInterval = 24 * 3600
    /// At most this many searches per refresh.
    public static let maxRequestsPerRefresh = 6
    /// At most this many searches run at the same time.
    public static let maxConcurrentRequests = 2

    private(set) var events: [PlayEvent] = []
    private(set) var profile = TasteProfile()
    private(set) var recommendations: [Recommendation] = []
    /// Library tracks worth hearing again, with no network needed.
    private(set) var rediscover: [Recommendation] = []
    private(set) var isRefreshing = false
    private(set) var lastRefresh: Date?
    private(set) var lastError: String?
    /// Off when the listener turns recommendations down.
    public var isEnabled = true

    @ObservationIgnored private let store: PlayEventStore
    @ObservationIgnored private let search: RecommendationSearch?
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var cachedCandidates: [Track] = []
    @ObservationIgnored private var candidatesFetchedAt: Date?
    @ObservationIgnored private var bootstrapped = false

    public init(
        store: PlayEventStore,
        search: RecommendationSearch? = nil,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.store = store
        self.search = search
        self.now = now
    }

    // MARK: - State

    public var isColdStart: Bool { profile.isColdStart }
    public var eventCount: Int { events.count }

    /// True when the listener may see recommendations at all.
    public var canRecommend: Bool {
        isEnabled && !isColdStart && !recommendations.isEmpty
    }

    // MARK: - Events

    public func load() {
        events = store.load().events
        profile = TasteProfile.build(events: events, now: now())
    }

    /// Records a listening event and refreshes the profile.
    public func record(_ event: PlayEvent) {
        events.append(event)
        if events.count > PlayEventStore.maxEvents {
            events = Array(events.suffix(PlayEventStore.maxEvents))
        }
        profile = TasteProfile.build(events: events, now: now())
        persist()
    }

    /// Seeds the profile once from the favourites and recents that already
    /// existed before the log started.
    public func bootstrapOnce(favorites: [Track], recents: [Track]) {
        guard !bootstrapped else { return }
        bootstrapped = true
        let stamp = now()
        for track in favorites {
            record(PlayEvent(
                source: track.provider,
                trackID: track.id,
                artist: track.artist,
                album: track.album,
                startedAt: stamp,
                outcome: .favorited
            ))
        }
        for track in recents.prefix(20) {
            record(PlayEvent(
                source: track.provider,
                trackID: track.id,
                artist: track.artist,
                album: track.album,
                startedAt: stamp,
                listenedSeconds: track.durationSeconds ?? 0,
                duration: track.durationSeconds ?? 0,
                outcome: .completed
            ))
        }
    }

    public func moreLikeThis(_ track: Track) {
        record(PlayEvent(
            source: track.provider,
            trackID: track.id,
            artist: track.artist,
            album: track.album,
            startedAt: now(),
            outcome: .moreLikeThis
        ))
    }

    public func notForMe(_ track: Track) {
        record(PlayEvent(
            source: track.provider,
            trackID: track.id,
            artist: track.artist,
            album: track.album,
            startedAt: now(),
            outcome: .notForMe
        ))
    }

    /// Clears the log and the derived state.
    public func reset() {
        events = []
        profile = TasteProfile()
        recommendations = []
        rediscover = []
        cachedCandidates = []
        candidatesFetchedAt = nil
        lastRefresh = nil
        bootstrapped = false
        persist()
    }

    private func persist() {
        try? store.save(PlayEventStore.Content(events: events))
    }

    // MARK: - Candidates

    /// Refreshes the shelf. Requests are limited, spaced and cached for a day.
    public func refresh(library: [Track] = []) async {
        guard isEnabled, !isColdStart, let search else { return }
        let stamp = now()
        if let candidatesFetchedAt,
           stamp.timeIntervalSince(candidatesFetchedAt) < Self.candidateLifetime,
           !cachedCandidates.isEmpty {
            applyRanking(library: library)
            return
        }
        if let lastRefresh, stamp.timeIntervalSince(lastRefresh) < Self.refreshInterval {
            // Too soon for another round of searches; keep what we have.
            applyRanking(library: library)
            return
        }

        isRefreshing = true
        lastError = nil
        defer { isRefreshing = false }

        let artists = Array(profile.topArtists.prefix(3))
        var candidates: [Track] = []
        var requests = 0
        var failures = 0
        for artist in artists {
            guard requests < Self.maxRequestsPerRefresh else { break }
            requests += 1
            do {
                let found = try await search(artist)
                candidates.append(contentsOf: found)
            } catch {
                failures += 1
                lastError = error.localizedDescription
            }
        }
        // The albums of the top artists fill the list when tracks are few.
        for album in profile.topAlbums.prefix(3) where requests < Self.maxRequestsPerRefresh {
            requests += 1
            do {
                let found = try await search(album)
                candidates.append(contentsOf: found)
            } catch {
                failures += 1
                lastError = error.localizedDescription
            }
        }

        if failures == requests, requests > 0 {
            // Nothing worked: keep the old candidates rather than empty the shelf.
            applyRanking(library: library)
            return
        }
        cachedCandidates = deduplicated(candidates)
        candidatesFetchedAt = stamp
        lastRefresh = stamp
        applyRanking(library: library)
    }

    private func applyRanking(library: [Track]) {
        recommendations = RecommendationRanker.rank(
            candidates: cachedCandidates,
            profile: profile,
            library: library
        )
        rediscover = RecommendationRanker.rank(
            candidates: library,
            profile: profile,
            library: []
        )
    }

    private func deduplicated(_ tracks: [Track]) -> [Track] {
        var seen = Set<String>()
        var result: [Track] = []
        for track in tracks {
            guard !seen.contains(track.sourceKey) else { continue }
            seen.insert(track.sourceKey)
            result.append(track)
        }
        return result
    }
}
