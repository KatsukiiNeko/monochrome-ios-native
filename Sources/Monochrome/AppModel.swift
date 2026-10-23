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
    private(set) var searchRecents: [Track] = []
    private(set) var errorMessage: String?
    private(set) var isImporting = false

    let player: PlayerController
    let cache: AudioCache
    let downloadStore: DownloadStore
    private(set) var streamingHost: String
    private(set) var isStreamingConfigured: Bool
    private(set) var appearanceMode: AppearanceMode
    private(set) var cacheSizeBytes = 0
    private(set) var cacheEntryCount = 0
    private(set) var cachedTracks: [CachedTrackSummary] = []
    private(set) var downloads: [DownloadItem] = []
    var allowsCellularCaching: Bool { cacheSettings.allowsCellular }
    var clearTemporaryCacheOnLaunch: Bool { cacheSettings.clearOnLaunch }

    private let service: LocalFileService
    private let favoritesStore: FavoritesStore
    private let historyStore: HistoryStore
    private let searchHistoryStore: HistoryStore
    private let resolver: DefaultTrackResolver
    private let streamingSettings: StreamingSettings
    private let appearanceSettings: AppearanceSettings
    private let cacheSettings: AudioCacheSettings
    private var streamingClient: TracksAPIClient?
    private let mediaDirectory: URL
    private let audioSession: AudioSessionController
    private let nowPlaying: NowPlayingController
    private let artworkTints = ArtworkTintStore()
    /// Cache cleanup is launch-only; import/delete reloads must not touch a download.
    private var didReconcileCache = false
    private var didReconcileDownloads = false

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
        let cacheSettings = AudioCacheSettings()
        // Temporary cache only. Permanent user files live in Application Support
        // and must never be moved under this directory.
        let cacheDirectory = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AudioCache", isDirectory: true)
        var excluded = cacheDirectory
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? excluded.setResourceValues(resourceValues)
        let cache = AudioCache(
            directory: cacheDirectory,
            downloader: URLSessionFileDownloader(allowsCellular: {
                UserDefaults.standard.bool(forKey: AudioCacheSettings.storageKey)
            }),
            allowsExpensiveNetwork: {
                UserDefaults.standard.bool(forKey: AudioCacheSettings.storageKey)
            },
            log: { message in playerLog.notice("\(message, privacy: .public)") }
        )
        // Permanent downloads live beside the library, not under Caches.
        let downloadsDirectory = base.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
        var excludedDownloads = downloadsDirectory
        var downloadValues = URLResourceValues()
        downloadValues.isExcludedFromBackup = true
        try? excludedDownloads.setResourceValues(downloadValues)
        let downloadStore = DownloadStore(
            directory: downloadsDirectory,
            downloader: URLSessionFileDownloader(allowsCellular: { true }),
            log: { message in playerLog.notice("\(message, privacy: .public)") }
        )
        let player = PlayerController(
            engine: AVPlayerEngine(),
            resolver: resolver,
            cache: cache,
            downloads: downloadStore
        )
        player.log = { message in playerLog.notice("\(message, privacy: .public)") }
        let settings = StreamingSettings()
        let appearanceSettings = AppearanceSettings()
        self.service = service
        self.player = player
        self.cache = cache
        self.downloadStore = downloadStore
        self.cacheSettings = cacheSettings
        self.resolver = resolver
        self.streamingSettings = settings
        self.appearanceSettings = appearanceSettings
        self.appearanceMode = appearanceSettings.mode
        self.streamingHost = settings.rawValue
        self.isStreamingConfigured = settings.baseURL != nil
        self.mediaDirectory = media
        self.favoritesStore = FavoritesStore(fileURL: base.appendingPathComponent("favorites.json"))
        self.historyStore = HistoryStore(fileURL: base.appendingPathComponent("history.json"))
        self.searchHistoryStore = HistoryStore(
            fileURL: base.appendingPathComponent("search-history.json"),
            limit: 10
        )
        // System integration: audio session first, then Lock Screen metadata/commands.
        self.audioSession = AudioSessionController(player: player)
        self.nowPlaying = NowPlayingController(player: player) { track in
            if let name = track.artworkFileName, !name.isEmpty {
                return media.appendingPathComponent(name)
            }
            return track.artworkURL
        }
        applyStreamingSettings()
        // One source of truth: every track the player actually starts lands in history.
        player.onTrackStarted = { [weak self] track in self?.record(track) }
    }

    // MARK: - Appearance

    func setAppearanceMode(_ mode: AppearanceMode) {
        appearanceSettings.setMode(mode)
        appearanceMode = mode
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

    /// Keeps the Search tab's empty state useful without a separate history model.
    func recordSearch(_ track: Track) {
        searchRecents = (try? searchHistoryStore.record(track)) ?? searchRecents
    }

    func removeSearchRecent(_ track: Track) {
        searchRecents.removeAll { $0.id == track.id }
        try? searchHistoryStore.save(searchRecents)
    }

    func clearSearchRecents() {
        searchRecents = []
        try? searchHistoryStore.save([])
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
        // Launch is the safe boundary for interrupted-write and orphan cleanup.
        if !didReconcileCache {
            if cacheSettings.clearOnLaunch {
                await cache.clear()
            } else {
                await cache.reconcile()
            }
            didReconcileCache = true
        }
        if !didReconcileDownloads {
            await downloadStore.reconcile()
            didReconcileDownloads = true
        }
        do {
            tracks = try await service.allTracks()
        } catch {
            errorMessage = "The music library could not be read: \(error.localizedDescription)"
            tracks = []
        }
        favorites = loadFavorites()
        recents = (try? historyStore.load()) ?? []
        searchRecents = (try? searchHistoryStore.load()) ?? []
        await refreshCacheSize()
        await refreshDownloads()
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

    // MARK: - Cache

    func refreshCacheSize() async {
        let tracks = await cache.cachedTracks()
        // Old sidecars have no display metadata; fill it from anything already loaded.
        var known: [String: Track] = [:]
        for track in self.tracks + recents + searchRecents + favorites {
            known[track.id] = track
        }
        cachedTracks = tracks.map { summary in
            guard let track = known[summary.trackID] else { return summary }
            var enriched = summary
            if enriched.title == nil { enriched.title = track.title }
            if enriched.artist == nil { enriched.artist = track.displayArtist }
            if enriched.artworkURL == nil { enriched.artworkURL = track.artworkURL }
            return enriched
        }
        cacheEntryCount = cachedTracks.count
        cacheSizeBytes = cachedTracks.reduce(0) { $0 + $1.byteSize }
    }

    func removeCachedTrack(_ track: CachedTrackSummary) async {
        await cache.remove(trackID: track.trackID, qualityName: track.quality)
        await refreshCacheSize()
    }

    func clearCache() async {
        await cache.clear()
        await refreshCacheSize()
    }

    func setAllowsCellularCaching(_ allowed: Bool) {
        cacheSettings.setAllowsCellular(allowed)
    }

    func setClearTemporaryCacheOnLaunch(_ clear: Bool) {
        cacheSettings.setClearOnLaunch(clear)
    }

    // MARK: - Permanent downloads

    var completedDownloads: [DownloadItem] {
        downloads.filter { $0.state == .completed }
    }

    var downloadsBytes: Int {
        completedDownloads.reduce(0) { $0 + ($1.record?.byteSize ?? 0) }
    }

    func isDownloaded(_ track: Track) -> Bool {
        completedDownloads.contains { $0.track.id == track.id }
    }

    func downloadState(for track: Track) -> DownloadState? {
        downloads.first { $0.track.id == track.id }?.state
    }

    func startDownload(_ track: Track) {
        guard track.source.supportsDownloads else {
            errorMessage = track.source.downloadUnavailableReason
            return
        }
        Task { await performDownload(track) }
    }

    private func performDownload(_ track: Track) async {
        do {
            let url = try await resolver.url(for: track)
            let contentType = await resolver.contentType(for: track)
            let poll = Task {
                while !Task.isCancelled {
                    await refreshDownloads()
                    try? await Task.sleep(for: .milliseconds(300))
                }
            }
            defer {
                poll.cancel()
                Task { await refreshDownloads() }
            }
            try await downloadStore.download(
                track: track,
                url: url,
                contentType: contentType,
                format: nil,
                duration: track.durationSeconds
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        await refreshDownloads()
    }

    func refreshDownloads() async {
        downloads = await downloadStore.items()
    }

    func removeDownload(_ item: DownloadItem) async {
        do {
            try await downloadStore.remove(id: item.id)
            await refreshDownloads()
        } catch {
            errorMessage = error.localizedDescription
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

    func artworkTint(for track: Track?) async -> ArtworkTintColor {
        guard let track else { return .neutral }
        return await artworkTints.tint(for: track, localURL: artworkURL(for: track))
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
