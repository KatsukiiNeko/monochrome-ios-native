// MusicService.swift: the seam between the app and whatever provides tracks.
import Foundation

public struct TrackMetadata: Equatable, Sendable {
    public var title: String?
    public var artist: String?
    public var album: String?
    public var durationSeconds: Double?
    public var artworkData: Data?

    public init(
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        durationSeconds: Double? = nil,
        artworkData: Data? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.durationSeconds = durationSeconds
        self.artworkData = artworkData
    }
}

/// Implemented by the iOS layer with AVFoundation.
public protocol TrackMetadataReading: Sendable {
    func metadata(for url: URL) async -> TrackMetadata?
}

public protocol MusicService: Sendable {
    func allTracks() async throws -> [Track]
    /// `fallbackTitle` is used when the file carries no title tag.
    func importTrack(from url: URL, fallbackTitle: String?) async throws -> Track
    func delete(_ track: Track) async throws
}
