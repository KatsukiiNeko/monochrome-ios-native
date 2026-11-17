// RecommendationModel.swift: the app-facing state of the listening log.
#if canImport(SwiftUI)
import Foundation
import MonochromeCore
import Observation

/// Owns the recommendation engine for the views. It records what the player
/// played, keeps the shelf fresh and carries the feedback actions.
@MainActor
@Observable
final class RecommendationModel {
    @ObservationIgnored private let engine: RecommendationEngine
    @ObservationIgnored private let player: PlayerController
    @ObservationIgnored private let library: () -> [Track]
    @ObservationIgnored private var knownFavoriteIDs: Set<String> = []
    @ObservationIgnored private var knownDownloadIDs: Set<String> = []
    @ObservationIgnored private var didBootstrap = false

    init(
        player: PlayerController,
        search: @escaping RecommendationSearch,
        library: @escaping () -> [Track],
        storeURL: URL? = nil
    ) {
        self.player = player
        self.library = library
        let engine = RecommendationEngine(
            store: PlayEventStore(fileURL: storeURL ?? Self.defaultStoreURL()),
            search: search
        )
        self.engine = engine
        engine.load()
        player.onPlayEvent = { [weak engine] event in
            engine?.record(event)
        }
    }

    /// The log lives beside the other app data but stays out of backups.
    private static func defaultStoreURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Monochrome", isDirectory: true)
        return base.appendingPathComponent("listening-log.json")
    }

    // MARK: - State

    var recommendations: [Recommendation] { engine.recommendations }
    var rediscover: [Recommendation] { engine.rediscover }
    var isRefreshing: Bool { engine.isRefreshing }
    var errorMessage: String? { engine.lastError }
    var isEnabled: Bool { engine.isEnabled }
    var isColdStart: Bool { engine.isColdStart }
    var eventCount: Int { engine.eventCount }

    // MARK: - Actions

    /// Seeds the profile once from the favourites and recents that already
    /// existed before the log started.
    func bootstrap(favorites: [Track], recents: [Track]) {
        guard !didBootstrap else { return }
        didBootstrap = true
        engine.bootstrapOnce(favorites: favorites, recents: recents)
        knownFavoriteIDs = Set(favorites.map(\.id))
    }

    /// Records favourites and finished downloads that appeared since the last
    /// check; a track that is already known is not counted twice.
    func syncSignals(favorites: [Track], downloads: [Track]) {
        for track in favorites where !knownFavoriteIDs.contains(track.id) {
            engine.record(PlayEvent(
                source: track.provider,
                trackID: track.id,
                artist: track.artist,
                album: track.album,
                startedAt: .now,
                outcome: .favorited
            ))
        }
        knownFavoriteIDs = Set(favorites.map(\.id))
        for track in downloads where !knownDownloadIDs.contains(track.id) {
            engine.record(PlayEvent(
                source: track.provider,
                trackID: track.id,
                artist: track.artist,
                album: track.album,
                startedAt: .now,
                outcome: .downloaded
            ))
        }
        knownDownloadIDs = Set(downloads.map(\.id))
    }

    /// Refreshes the shelf; the engine keeps the rate and the request budget.
    func refreshIfNeeded() async {
        guard engine.isEnabled else { return }
        await engine.refresh(library: library())
    }

    /// Asks for more tracks like this one.
    func moreLikeThis(_ track: Track) {
        engine.moreLikeThis(track)
    }

    /// Marks a track as not wanted.
    func notForMe(_ track: Track) {
        engine.notForMe(track)
    }

    /// Turns the shelf on or off.
    func setEnabled(_ enabled: Bool) {
        engine.setEnabled(enabled)
    }

    /// Clears the listening log and the taste it built.
    func resetTasteProfile() {
        engine.reset()
        knownFavoriteIDs = []
        knownDownloadIDs = []
    }
}
#endif
