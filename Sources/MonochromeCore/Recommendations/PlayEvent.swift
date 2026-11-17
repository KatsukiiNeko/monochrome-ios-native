// PlayEvent.swift: the listening log that feeds the taste profile.
import Foundation

/// One thing the listener did with a track. The log stays on the device.
public struct PlayEvent: Codable, Equatable, Sendable, Identifiable {
    public enum Outcome: String, Codable, Sendable {
        case completed
        case skipped
        case favorited
        case downloaded
        case moreLikeThis
        case notForMe
    }

    public var id: UUID
    /// Provider of the track, e.g. "monochrome" or "local".
    public var source: String
    public var trackID: String
    public var artist: String
    public var album: String
    public var startedAt: Date
    public var listenedSeconds: Double
    public var duration: Double
    public var outcome: Outcome
    /// True when the track was replayed instead of moving on.
    public var loop: Bool

    public init(
        id: UUID = UUID(),
        source: String,
        trackID: String,
        artist: String,
        album: String,
        startedAt: Date,
        listenedSeconds: Double = 0,
        duration: Double = 0,
        outcome: Outcome,
        loop: Bool = false
    ) {
        self.id = id
        self.source = source
        self.trackID = trackID
        self.artist = artist
        self.album = album
        self.startedAt = startedAt
        self.listenedSeconds = listenedSeconds
        self.duration = duration
        self.outcome = outcome
        self.loop = loop
    }

    /// The key that identifies the track across providers.
    public var trackKey: String { "\(source)|\(trackID)" }

    /// The part of the track that was actually heard, 0...1.
    public var listenedFraction: Double {
        guard duration > 0 else { return outcome == .completed ? 1 : 0 }
        return min(1, max(0, listenedSeconds / duration))
    }
}

/// The event log on disk: versioned, capped and quarantined when corrupt.
public struct PlayEventStore: Sendable {
    public static let schemaVersion = 1
    /// The log grows with listening; the cap keeps it bounded.
    public static let maxEvents = 5000
    public static let maxBytes = 4 * 1024 * 1024

    public struct Content: Codable, Equatable, Sendable {
        public var schemaVersion: Int
        public var events: [PlayEvent]

        public init(events: [PlayEvent] = []) {
            self.schemaVersion = PlayEventStore.schemaVersion
            self.events = events
        }

        private enum CodingKeys: String, CodingKey { case schemaVersion, events }

        /// A file written before the version field existed migrates in place.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
                ?? PlayEventStore.schemaVersion
            events = try container.decodeIfPresent([PlayEvent].self, forKey: .events) ?? []
        }
    }

    private let file: JSONFileStore

    public init(fileURL: URL) {
        self.file = JSONFileStore(fileURL: fileURL, maxBytes: Self.maxBytes)
    }

    public func load() -> Content {
        file.read(Content.self) ?? Content()
    }

    /// Keeps the newest events when the cap is reached.
    public func save(_ content: Content) throws {
        var trimmed = content
        if trimmed.events.count > Self.maxEvents {
            trimmed.events = Array(trimmed.events.suffix(Self.maxEvents))
        }
        try file.write(trimmed)
    }
}
