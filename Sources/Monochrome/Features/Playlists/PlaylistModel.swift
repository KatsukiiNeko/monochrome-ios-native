// PlaylistModel.swift: playlist state and persistence for the views.
#if canImport(SwiftUI)
import Foundation
import MonochromeCore
import Observation

/// Owns the user's playlists. A mutation is written before it is published, so
/// the UI never shows a playlist that failed to save.
@MainActor
@Observable
final class PlaylistModel {
    private(set) var collection = PlaylistCollection()
    private(set) var errorMessage: String?

    @ObservationIgnored private let store: PlaylistStore

    init(fileURL: URL? = nil) {
        self.store = PlaylistStore(
            fileURL: fileURL ?? Self.defaultFileURL(),
            log: { message in playerLog.notice("\(message, privacy: .public)") }
        )
    }

    /// Playlists are user data, so they live beside the library and are backed up.
    private static func defaultFileURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Monochrome", isDirectory: true)
            .appendingPathComponent("playlists.json")
    }

    // MARK: - Reads

    var playlists: [Playlist] { collection.playlists }

    func playlist(id: String) -> Playlist? { collection.playlist(id: id) }

    func load() {
        collection = store.load()
    }

    func clearError() {
        errorMessage = nil
    }

    // MARK: - Mutations

    @discardableResult
    func create(named name: String) -> Playlist? {
        var updated = collection
        guard let playlist = updated.create(named: name, now: .now) else {
            errorMessage = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "A playlist needs a name."
                : "You can keep up to \(PlaylistCollection.maxPlaylists) playlists."
            return nil
        }
        return commit(updated) ? playlist : nil
    }

    @discardableResult
    func rename(id: String, to name: String) -> Bool {
        var updated = collection
        guard updated.rename(id: id, to: name, now: .now) else {
            errorMessage = "The playlist could not be renamed."
            return false
        }
        return commit(updated)
    }

    @discardableResult
    func delete(id: String) -> Bool {
        var updated = collection
        guard updated.delete(id: id) else { return false }
        return commit(updated)
    }

    @discardableResult
    func duplicate(id: String) -> Playlist? {
        var updated = collection
        guard let copy = updated.duplicate(id: id, now: .now) else {
            errorMessage = "You can keep up to \(PlaylistCollection.maxPlaylists) playlists."
            return nil
        }
        return commit(updated) ? copy : nil
    }

    @discardableResult
    func add(_ track: Track, to playlistID: String, allowDuplicate: Bool = false) -> PlaylistAddResult {
        var updated = collection
        let result = updated.add(track, to: playlistID, allowDuplicate: allowDuplicate, now: .now)
        switch result {
        case .added:
            guard commit(updated) else { return .playlistNotFound }
        case .playlistFull:
            errorMessage = "This playlist is full."
        case .playlistNotFound:
            errorMessage = "The playlist could not be found."
        case .playlistLimitReached:
            errorMessage = "You can keep up to \(PlaylistCollection.maxPlaylists) playlists."
        case .duplicate:
            break
        }
        return result
    }

    /// Adds several tracks in one write; duplicates are skipped.
    @discardableResult
    func add(_ tracks: [Track], to playlistID: String) -> Int {
        var updated = collection
        let added = updated.add(tracks, to: playlistID, now: .now)
        guard added > 0 else { return 0 }
        return commit(updated) ? added : 0
    }

    func removeItem(at index: Int, from playlistID: String) {
        var updated = collection
        guard updated.remove(at: index, from: playlistID, now: .now) != nil else { return }
        commit(updated)
    }

    func moveTrack(in playlistID: String, from source: Int, to destination: Int) {
        var updated = collection
        updated.moveTrack(in: playlistID, from: source, to: destination, now: .now)
        guard updated != collection else { return }
        commit(updated)
    }

    // MARK: - Persistence

    private func commit(_ updated: PlaylistCollection) -> Bool {
        do {
            try store.save(updated)
            collection = updated
            errorMessage = nil
            return true
        } catch {
            errorMessage = "The playlist could not be saved: \(error.localizedDescription)"
            return false
        }
    }
}
#endif
