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

    public init(
        id: String = UUID().uuidString,
        title: String,
        artist: String = "",
        album: String = "",
        durationSeconds: Double? = nil,
        fileName: String,
        importedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.durationSeconds = durationSeconds
        self.fileName = fileName
        self.importedAt = importedAt
    }
}
