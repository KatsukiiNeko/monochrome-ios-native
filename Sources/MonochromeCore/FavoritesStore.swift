// FavoritesStore.swift: favorite tracks persisted as JSON (v1 stored ids only).
import Foundation

public enum FavoritesContent: Equatable, Sendable {
    case tracks([Track])
    /// The v1 format: ids without metadata, resolved against the library on load.
    case legacyIDs([String])
}

public struct FavoritesStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> FavoritesContent {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .tracks([]) }
        let data = try Data(contentsOf: fileURL)
        if let tracks = try? JSONDecoder().decode([Track].self, from: data) {
            return .tracks(tracks)
        }
        return .legacyIDs(try JSONDecoder().decode([String].self, from: data))
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
