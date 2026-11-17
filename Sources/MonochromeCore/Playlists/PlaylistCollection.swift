// PlaylistCollection.swift: every mutation rule for the user's playlists.
import Foundation

public enum PlaylistAddResult: Equatable, Sendable {
    case added
    case duplicate
    case playlistFull
    case playlistNotFound
    case playlistLimitReached
}

public struct PlaylistCollection: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public static let maxPlaylists = 200
    public static let maxTracksPerPlaylist = 5000

    public var schemaVersion: Int
    public private(set) var playlists: [Playlist]

    public init(playlists: [Playlist] = []) {
        self.schemaVersion = Self.schemaVersion
        self.playlists = playlists
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, playlists }

    /// A file without a version is the pre-versioned layout: it migrates in place.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? PlaylistCollection.schemaVersion
        playlists = try container.decodeIfPresent([Playlist].self, forKey: .playlists) ?? []
    }

    public func playlist(id: String) -> Playlist? {
        playlists.first { $0.id == id }
    }

    public var trackCount: Int {
        playlists.reduce(0) { $0 + $1.items.count }
    }

    // MARK: - Mutations

    /// An empty or blank name creates nothing.
    @discardableResult
    public mutating func create(named rawName: String, now: Date) -> Playlist? {
        let name = Self.trimmedName(rawName)
        guard !name.isEmpty, playlists.count < Self.maxPlaylists else { return nil }
        let playlist = Playlist(name: name, createdAt: now, updatedAt: now)
        playlists.append(playlist)
        return playlist
    }

    @discardableResult
    public mutating func rename(id: String, to rawName: String, now: Date) -> Bool {
        let name = Self.trimmedName(rawName)
        guard !name.isEmpty, let index = playlists.firstIndex(where: { $0.id == id }) else { return false }
        playlists[index].name = name
        playlists[index].updatedAt = now
        return true
    }

    @discardableResult
    public mutating func delete(id: String) -> Bool {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return false }
        playlists.remove(at: index)
        return true
    }

    /// Copies items; the copy gets a fresh id so mutations stay independent.
    @discardableResult
    public mutating func duplicate(id: String, now: Date) -> Playlist? {
        guard let source = playlist(id: id), playlists.count < Self.maxPlaylists else { return nil }
        let copy = Playlist(name: source.name + " Copy", createdAt: now, updatedAt: now, items: source.items)
        playlists.append(copy)
        return copy
    }

    @discardableResult
    public mutating func add(
        _ track: Track,
        to playlistID: String,
        allowDuplicate: Bool = false,
        now: Date
    ) -> PlaylistAddResult {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else {
            return .playlistNotFound
        }
        guard playlists[index].items.count < Self.maxTracksPerPlaylist else { return .playlistFull }
        guard allowDuplicate || !playlists[index].contains(track) else { return .duplicate }
        playlists[index].items.append(track)
        playlists[index].updatedAt = now
        return .added
    }

    /// Appends several tracks at once, keeping already-present ones out.
    public mutating func add(_ tracks: [Track], to playlistID: String, now: Date) -> Int {
        var added = 0
        for track in tracks {
            if add(track, to: playlistID, now: now) == .added { added += 1 }
        }
        return added
    }

    @discardableResult
    public mutating func remove(at itemIndex: Int, from playlistID: String, now: Date) -> Track? {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }),
              playlists[index].items.indices.contains(itemIndex) else { return nil }
        let removed = playlists[index].items.remove(at: itemIndex)
        playlists[index].updatedAt = now
        return removed
    }

    /// `destination` follows Array.move semantics, like the queue reorder.
    public mutating func moveTrack(in playlistID: String, from source: Int, to destination: Int, now: Date) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        var items = playlists[index].items
        guard items.indices.contains(source), (0...items.count).contains(destination) else { return }
        let moved = items.remove(at: source)
        let adjusted = destination > source ? destination - 1 : destination
        items.insert(moved, at: min(adjusted, items.count))
        playlists[index].items = items
        playlists[index].updatedAt = now
    }

    /// Drops entries whose track no longer exists anywhere; called on library reload.
    public mutating func pruneTracks(matching shouldRemove: (Track) -> Bool, now: Date) {
        for index in playlists.indices where !playlists[index].items.isEmpty {
            let filtered = playlists[index].items.filter { !shouldRemove($0) }
            if filtered.count != playlists[index].items.count {
                playlists[index].items = filtered
                playlists[index].updatedAt = now
            }
        }
    }

    static func trimmedName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
