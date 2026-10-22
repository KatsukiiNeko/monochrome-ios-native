// Track.swift: the portable track model shared by the library and the player.
import Foundation

public struct Track: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var artist: String
    public var album: String
    public var durationSeconds: Double?
    /// File name inside the app's managed media directory.
    public var fileName: String
    public var importedAt: Date
    /// Optional artwork file name (same directory as `fileName`).
    public var artworkFileName: String?

    public init(
        id: String = UUID().uuidString,
        title: String,
        artist: String = "",
        album: String = "",
        durationSeconds: Double? = nil,
        fileName: String,
        importedAt: Date = .now,
        artworkFileName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.durationSeconds = durationSeconds
        self.fileName = fileName
        self.importedAt = importedAt
        self.artworkFileName = artworkFileName
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, artist, album, durationSeconds, fileName, importedAt, artworkFileName
    }

    // Tolerant decoding: a hand-edited or older library.json must not fail the app.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled"
        artist = try container.decodeIfPresent(String.self, forKey: .artist) ?? ""
        album = try container.decodeIfPresent(String.self, forKey: .album) ?? ""
        durationSeconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds)
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName) ?? ""
        importedAt = try container.decodeIfPresent(Date.self, forKey: .importedAt) ?? .distantPast
        artworkFileName = try container.decodeIfPresent(String.self, forKey: .artworkFileName)
    }
}

extension Track {
    public var displayArtist: String { artist.isEmpty ? "Unknown artist" : artist }
    public var displayAlbum: String { album.isEmpty ? "Unknown album" : album }
}
