// Playlist.swift: a named, ordered list of track snapshots that renders offline.
import Foundation

/// The stored item is a full `Track` snapshot: id, source, title, artist, album,
/// duration and artwork URL, so a playlist renders without the catalog.
public struct Playlist: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date
    public var items: [Track]

    public init(id: String = UUID().uuidString, name: String, createdAt: Date, updatedAt: Date, items: [Track] = []) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.items = items
    }

    private enum CodingKeys: String, CodingKey { case id, name, createdAt, updatedAt, items }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        items = try container.decodeIfPresent([Track].self, forKey: .items) ?? []
    }

    /// A playlist is keyed by the track's source and id: the same song twice is
    /// a duplicate unless the user allows it.
    func contains(_ track: Track) -> Bool {
        items.contains { $0.sourceKey == track.sourceKey }
    }
}

extension Track {
    /// The identity a playlist deduplicates on: source plus id.
    var sourceKey: String { "\(provider)|\(id)" }
}
