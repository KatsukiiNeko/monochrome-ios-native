// Track.swift: the portable track model shared by the library and the player.
import Foundation

public struct Track: Codable, Equatable, Identifiable, Sendable {
    /// Provider value for a file in the app's managed media directory.
    public static let localProvider = "local"
    /// Prefix that keeps catalog ids from colliding with local UUIDs.
    public static let remoteIDPrefix = "stream:"

    public var id: String
    public var title: String
    public var artist: String
    public var album: String
    public var durationSeconds: Double?
    /// File name inside the app's managed media directory; empty for streams.
    public var fileName: String
    public var importedAt: Date
    /// Optional artwork file name (same directory as `fileName`).
    public var artworkFileName: String?
    /// `local` or the catalog that supplies the stream.
    public var provider: String
    /// Catalog id used to build the stream URL; nil for local files.
    public var streamID: String?
    /// Remote artwork, used when `artworkFileName` is absent.
    public var artworkURL: URL?

    public init(
        id: String = UUID().uuidString,
        title: String,
        artist: String = "",
        album: String = "",
        durationSeconds: Double? = nil,
        fileName: String = "",
        importedAt: Date = .now,
        artworkFileName: String? = nil,
        provider: String = Track.localProvider,
        streamID: String? = nil,
        artworkURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.durationSeconds = durationSeconds
        self.fileName = fileName
        self.importedAt = importedAt
        self.artworkFileName = artworkFileName
        self.provider = provider
        self.streamID = streamID
        self.artworkURL = artworkURL
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, artist, album, durationSeconds, fileName, importedAt, artworkFileName
        case provider, streamID, artworkURL
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
        provider = try container.decodeIfPresent(String.self, forKey: .provider) ?? Self.localProvider
        streamID = try container.decodeIfPresent(String.self, forKey: .streamID)
        artworkURL = (try? container.decodeIfPresent(URL.self, forKey: .artworkURL)) ?? nil
    }
}

extension Track {
    public var displayArtist: String { artist.isEmpty ? "Unknown artist" : artist }
    public var displayAlbum: String { album.isEmpty ? "Unknown album" : album }
    /// True when the audio has to be resolved from a catalog at play time.
    public var isStreaming: Bool { provider != Self.localProvider }
}
