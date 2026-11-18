// SourceResolver.swift: the same recording on the other source, cached and time-boxed.
import Foundation

/// What the resolver needs from a source. The catalog client conforms; the
/// companion server gets its own client behind this protocol.
public protocol SourceSearching: Sendable {
    func searchTracks(matching query: String, limit: Int) async throws -> [Track]
}

extension TracksAPIClient: SourceSearching {}

/// Prefers the HiFi copy of a companion track and finds the companion copy
/// when a HiFi stream fails. The queue keeps the tracks it was given; only the
/// track that is about to play is swapped. A search that times out leaves no
/// verdict, and a skip cancels the wait.
public struct SourceResolver: Sendable {
    /// A source search that takes longer than this is abandoned for this play.
    public static let defaultSearchBudget: Duration = .milliseconds(1500)
    public static let searchLimit = 10

    private let hifi: any SourceSearching
    private let companion: any SourceSearching
    private let store: SourceLinkStore
    private let matcher: TrackMatcher
    private let budget: Duration
    private let now: @Sendable () -> Date
    private let log: (@Sendable (String) -> Void)?

    public init(
        hifi: any SourceSearching,
        companion: any SourceSearching,
        store: SourceLinkStore,
        matcher: TrackMatcher = TrackMatcher(),
        budget: Duration = SourceResolver.defaultSearchBudget,
        now: @escaping @Sendable () -> Date = { .now },
        log: (@Sendable (String) -> Void)? = nil
    ) {
        self.hifi = hifi
        self.companion = companion
        self.store = store
        self.matcher = matcher
        self.budget = budget
        self.now = now
        self.log = log
    }

    /// The HiFi copy to play instead of a companion track.
    public func losslessCounterpart(for track: Track) async -> Track? {
        guard track.source == .youTubeMusic else { return nil }
        return await counterpart(for: track, source: hifi, provider: .monochrome)
    }

    /// The companion copy to fall back to after a HiFi stream fails.
    public func companionCounterpart(for track: Track) async -> Track? {
        guard track.source == .monochrome else { return nil }
        return await counterpart(for: track, source: companion, provider: .youTubeMusic)
    }

    /// The listener said the substituted copy is the wrong recording: keep the
    /// original until they clear it.
    public func useOriginal(for track: Track, counterpartProvider: MusicSourceID) {
        record(
            SourceLink(
                provider: track.provider,
                trackID: track.id,
                counterpartProvider: counterpartProvider.rawValue,
                counterpart: nil,
                state: .manual,
                method: .heuristic,
                confidence: 0,
                updatedAt: now()
            )
        )
    }

    public func clearVerdict(for track: Track, counterpartProvider: MusicSourceID) {
        do {
            try store.clear(
                provider: track.provider,
                trackID: track.id,
                counterpartProvider: counterpartProvider.rawValue
            )
        } catch {
            log?("source link clear failed error=\(error.localizedDescription)")
        }
    }

    /// One key for recommendations and radio, whichever copy actually played.
    public func canonicalKey(for track: Track) -> String {
        for counterpartProvider in MusicSourceID.allCases where counterpartProvider != track.source {
            let link = store.link(
                provider: track.provider,
                trackID: track.id,
                counterpartProvider: counterpartProvider.rawValue
            )
            if let counterpart = link?.counterpart {
                return counterpart.sourceKey
            }
        }
        return track.sourceKey
    }

    // MARK: - Internals

    private func counterpart(
        for track: Track,
        source: any SourceSearching,
        provider: MusicSourceID
    ) async -> Track? {
        if let link = store.link(
            provider: track.provider,
            trackID: track.id,
            counterpartProvider: provider.rawValue
        ) {
            return link.counterpart
        }

        guard let results = await search(source, query: Self.query(for: track)) else {
            // Timed out, failed or skipped: no verdict, so the next play retries.
            return nil
        }
        guard !Task.isCancelled else { return nil }

        let best = matcher.bestMatch(for: track, among: results.filter { $0.source == provider })
        record(
            SourceLink(
                provider: track.provider,
                trackID: track.id,
                counterpartProvider: provider.rawValue,
                counterpart: best?.track,
                state: best == nil ? .rejected : .confirmed,
                method: best?.match.method ?? .heuristic,
                confidence: best?.match.confidence ?? 0,
                updatedAt: now()
            )
        )
        log?(
            "source resolve track=\(track.id) counterpart=\(best?.track.id ?? "none") "
                + "confidence=\(best?.match.confidence ?? 0)"
        )
        return best?.track
    }

    private func search(_ source: any SourceSearching, query: String) async -> [Track]? {
        enum Outcome: Sendable {
            case results([Track])
            case failed
            case timedOut
        }
        let outcome = await withTaskGroup(of: Outcome.self) { group in
            group.addTask {
                do {
                    return .results(try await source.searchTracks(matching: query, limit: Self.searchLimit))
                } catch {
                    return .failed
                }
            }
            group.addTask {
                try? await Task.sleep(for: budget)
                return .timedOut
            }
            let first = await group.next() ?? .timedOut
            group.cancelAll()
            return first
        }
        if case .results(let tracks) = outcome { return tracks }
        return nil
    }

    private func record(_ link: SourceLink) {
        do {
            try store.record(link)
        } catch {
            log?("source link save failed error=\(error.localizedDescription)")
        }
    }

    /// Title plus artist is what both catalogs search best on.
    static func query(for track: Track) -> String {
        [track.title, track.artist].joined(separator: " ")
    }
}
