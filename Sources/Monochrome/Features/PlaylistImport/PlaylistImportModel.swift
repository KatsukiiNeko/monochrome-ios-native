// PlaylistImportModel.swift: drives a playlist import from a file to a new playlist.
#if canImport(SwiftUI)
import Foundation
import MonochromeCore
import Observation

/// Owns one import run: parsing, the search loop, the review list and the
/// final playlist write. The catalog search is injected so the model never
/// grows the app model.
@MainActor
@Observable
final class PlaylistImportModel {
    enum Phase: Equatable {
        case idle
        case matching
        case review
        case finished
    }

    private(set) var phase: Phase = .idle
    private(set) var formatName = ""
    private(set) var skippedLines = 0
    private(set) var playlistName = ""
    private(set) var errorMessage: String?
    /// Entries beyond the 500 cap that were not imported.
    private(set) var droppedCount = 0

    @ObservationIgnored private let importer = PlaylistImporter()
    @ObservationIgnored private let search: PlaylistSearch
    @ObservationIgnored private let playlists: PlaylistModel
    @ObservationIgnored private let progressURL: URL

    init(
        playlists: PlaylistModel,
        search: @escaping PlaylistSearch,
        progressURL: URL? = nil
    ) {
        self.playlists = playlists
        self.search = search
        self.progressURL = progressURL ?? Self.defaultProgressURL()
    }

    private static func defaultProgressURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Monochrome", isDirectory: true)
        return base.appendingPathComponent("playlist-import.json")
    }

    // MARK: - State

    var isRunning: Bool { importer.isRunning }
    var processedCount: Int { importer.processed }
    var totalCount: Int { importer.total }
    var progress: Double {
        guard importer.total > 0 else { return 0 }
        return Double(importer.processed) / Double(importer.total)
    }
    var reviewEntries: [PlaylistImportSettlement] { importer.reviewEntries }
    var matchedCount: Int { importer.chosenTracks.count }
    var summary: String { importer.summary }

    // MARK: - Actions

    /// Parses a picked file and starts matching its entries.
    func start(fileURL: URL) {
        let needsScope = fileURL.startAccessingSecurityScopedResource()
        defer { if needsScope { fileURL.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: fileURL) else {
            errorMessage = "The file could not be read."
            phase = .idle
            return
        }
        let parsed = PlaylistFileParser.parse(data)
        formatName = parsed.format.rawValue
        skippedLines = parsed.skipped
        playlistName = parsed.playlistName ?? fileURL.deletingPathExtension().lastPathComponent
        errorMessage = nil
        droppedCount = importer.start(
            name: playlistName,
            entries: parsed.entries,
            search: search,
            store: progressURL
        )
        phase = .matching
    }

    /// Continues a run that was interrupted earlier.
    func resume() {
        guard importer.resume(store: progressURL, search: search) else {
            errorMessage = "There is no unfinished import to continue."
            return
        }
        phase = .matching
    }

    var hasSavedProgress: Bool {
        PlaylistImporter.storedProgress(at: progressURL) != nil
    }

    func pause() {
        importer.pause()
        phase = .review
    }

    func cancel() {
        importer.discardProgress(fileURL: progressURL)
        phase = .idle
    }

    func choose(_ settlement: PlaylistImportSettlement, track: Track) {
        importer.choose(settlement, track: track)
    }

    func reject(_ settlement: PlaylistImportSettlement) {
        importer.reject(settlement)
    }

    /// Writes the matched tracks into a new playlist.
    @discardableResult
    func save(name: String? = nil) -> Bool {
        let tracks = importer.chosenTracks
        guard !tracks.isEmpty else {
            errorMessage = "There is nothing to save yet."
            return false
        }
        let trimmed = (name ?? playlistName).trimmingCharacters(in: .whitespacesAndNewlines)
        playlistName = trimmed.isEmpty ? "Imported Playlist" : trimmed
        guard let playlist = playlists.create(named: playlistName) else {
            errorMessage = playlists.errorMessage ?? "The playlist could not be created."
            return false
        }
        playlists.add(tracks, to: playlist.id)
        importer.discardProgress(fileURL: progressURL)
        phase = .finished
        return true
    }
}
#endif
