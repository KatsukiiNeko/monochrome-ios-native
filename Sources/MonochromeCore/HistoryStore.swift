// HistoryStore.swift: recently played tracks, newest first and capped.
import Foundation

public struct HistoryStore: Sendable {
    public let fileURL: URL
    public let limit: Int

    public init(fileURL: URL, limit: Int = 50) {
        self.fileURL = fileURL
        self.limit = limit
    }

    public func load() throws -> [Track] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([Track].self, from: data)
    }

    /// Replaying a track moves it to the front instead of duplicating it.
    @discardableResult
    public func record(_ track: Track) throws -> [Track] {
        // A corrupt history must not block playback, so an unreadable file starts over.
        var tracks = (try? load()) ?? []
        tracks.removeAll { $0.id == track.id }
        tracks.insert(track, at: 0)
        if tracks.count > limit {
            tracks.removeLast(tracks.count - limit)
        }
        try save(tracks)
        return tracks
    }

    public func save(_ tracks: [Track]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(tracks)
        try data.write(to: fileURL, options: .atomic)
    }
}
