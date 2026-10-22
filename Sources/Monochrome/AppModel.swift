// AppModel.swift: owns the library, import flow and player for the views.
#if canImport(SwiftUI)
import Foundation
import MonochromeCore
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var tracks: [Track] = []
    private(set) var favorites: [Track] = []
    private(set) var recents: [Track] = []
    private(set) var errorMessage: String?
    private(set) var isImporting = false

    let player: PlayerController
    private(set) var streamingHost: String
    private(set) var isStreamingConfigured: Bool

    private let service: LocalFileService
    private let favoritesStore: FavoritesStore
    private let historyStore: HistoryStore
    private let resolver: DefaultTrackResolver
    private let streamingSettings: StreamingSettings
    private var streamingClient: TracksAPIClient?
    private let mediaDirectory: URL
    private let audioSession: AudioSessionController
    private let nowPlaying: NowPlayingController

    init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Monochrome", isDirectory: true)
        let media = base.appendingPathComponent("Media", isDirectory: true)
        let service = LocalFileService(
            mediaDirectory: media,
            store: LibraryStore(fileURL: base.appendingPathComponent("library.json")),
            metadataReader: AVAssetMetadataReader()
        )
        let resolver = DefaultTrackResolver(localDirectory: media)
        let player = PlayerController(engine: AVPlayerEngine(), resolver: resolver)
        let settings = StreamingSettings()
        self.service = service
        self.player = player
        self.resolver = resolver
        self.streamingSettings = settings
        self.streamingHost = settings.rawValue
        self.isStreamingConfigured = settings.baseURL != nil
        self.mediaDirectory = media
        self.favoritesStore = FavoritesStore(fileURL: base.appendingPathComponent("favorites.json"))
        self.historyStore = HistoryStore(fileURL: base.appendingPathComponent("history.json"))
        // System integration: audio session first, then Lock Screen metadata/commands.
        self.audioSession = AudioSessionController(player: player)
        self.nowPlaying = NowPlayingController(player: player)
        applyStreamingSettings()
        // One source of truth: every track the player actually starts lands in history.
        player.onTrackStarted = { [weak self] track in self?.record(track) }
    }

    // MARK: - Streaming

    /// Rebuilds the client so a changed host takes effect without restarting the app.
    private func applyStreamingSettings() {
        let baseURL = streamingSettings.baseURL
        isStreamingConfigured = baseURL != nil
        let client = baseURL.map { TracksAPIClient(baseURL: $0) }
        streamingClient = client
        Task { await resolver.useStreamingClient(client) }
    }

    func saveStreamingHost(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Empty input is a deliberate "streaming off", not an invalid host.
        if !trimmed.isEmpty, StreamingSettings.baseURL(from: trimmed) == nil {
            return false
        }
        streamingSettings.setBaseURL(trimmed)
        streamingHost = streamingSettings.rawValue
        applyStreamingSettings()
        return true
    }

    func resetStreamingHost() {
        streamingSettings.reset()
        streamingHost = streamingSettings.rawValue
        applyStreamingSettings()
    }

    func searchTracks(_ query: String) async throws -> [Track] {
        try await requireClient().searchTracks(matching: query)
    }

    func searchReleases(_ query: String) async throws -> [RemoteRelease] {
        try await requireClient().searchReleases(matching: query)
    }

    func searchArtists(_ query: String) async throws -> [RemoteArtist] {
        try await requireClient().searchArtists(matching: query)
    }

    func releaseDetail(id: String) async throws -> RemoteReleaseDetail {
        try await requireClient().release(id: id)
    }

    func artistDetail(id: String) async throws -> RemoteArtistDetail {
        try await requireClient().artist(id: id)
    }

    private func requireClient() throws -> TracksAPIClient {
        guard let streamingClient else { throw TracksAPIError.notConfigured }
        return streamingClient
    }

    /// Plays a search result with the rest of the results as the queue.
    func play(_ track: Track, in results: [Track]) async {
        guard let index = results.firstIndex(where: { $0.id == track.id }) else { return }
        await player.play(tracks: results, startingAt: index)
    }

    func loadTracks() async {
        do {
            tracks = try await service.allTracks()
        } catch {
            errorMessage = "The music library could not be read: \(error.localizedDescription)"
            tracks = []
        }
        favorites = loadFavorites()
        recents = (try? historyStore.load()) ?? []
    }

    private func loadFavorites() -> [Track] {
        do {
            switch try favoritesStore.load() {
            case .tracks(let tracks):
                return tracks
            case .legacyIDs(let ids):
                // v1 stored ids only: keep what is still in the library and rewrite the file.
                let migrated = ids.compactMap { id in tracks.first { $0.id == id } }
                try? favoritesStore.save(migrated)
                return migrated
            }
        } catch {
            errorMessage = "Favorites could not be read: \(error.localizedDescription)"
            return []
        }
    }

    private func record(_ track: Track) {
        // History is a convenience: a failed write must never interrupt playback.
        recents = (try? historyStore.record(track)) ?? recents
    }

    func importFiles(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        isImporting = true
        defer { isImporting = false }

        var failures = 0
        for url in urls {
            // Files picked outside the app's container need scoped access to be read.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                _ = try await service.importTrack(from: url, fallbackTitle: nil)
            } catch {
                failures += 1
            }
        }
        await loadTracks()
        if failures > 0 {
            errorMessage = failures == 1
                ? "One file could not be imported."
                : "\(failures) files could not be imported."
        }
    }

    func play(_ track: Track) async {
        guard let index = tracks.firstIndex(where: { $0.id == track.id }) else { return }
        await player.play(tracks: tracks, startingAt: index)
    }

    func delete(_ track: Track) async {
        do {
            try await service.delete(track)
            if player.currentTrack?.id == track.id {
                await player.next()
            }
            await loadTracks()
        } catch {
            errorMessage = "The track could not be deleted: \(error.localizedDescription)"
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func report(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    func artworkURL(for track: Track?) -> URL? {
        guard let name = track?.artworkFileName else { return nil }
        return mediaDirectory.appendingPathComponent(name)
    }

    // MARK: - Favorites

    func isFavorite(_ track: Track) -> Bool {
        favorites.contains { $0.id == track.id }
    }

    func toggleFavorite(_ track: Track) {
        var updated = favorites
        if let index = updated.firstIndex(where: { $0.id == track.id }) {
            updated.remove(at: index)
        } else {
            updated.insert(track, at: 0)
        }
        do {
            try favoritesStore.save(updated)
            favorites = updated
        } catch {
            errorMessage = "The favorite could not be saved: \(error.localizedDescription)"
        }
    }
}
#endif
