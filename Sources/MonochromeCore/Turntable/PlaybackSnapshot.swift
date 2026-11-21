// PlaybackSnapshot.swift: what the app writes for the widget to compute from.
import Foundation

public struct PlaybackSnapshot: Codable, Equatable, Sendable {
    /// The platter turns at 33⅓ rpm clockwise, read as degrees on screen.
    public static let platterDegreesPerSecond = 200.0
    public var trackID: String?
    public var title: String
    public var artist: String
    public var duration: TimeInterval?
    /// Position when `date` was written.
    public var position: TimeInterval
    /// True only when the engine reports it is producing audio.
    public var isPlaying: Bool
    /// Absolute platter angle at `date`; never decreases.
    public var platterDegrees: Double
    public var date: Date
    public var playStartedAt: Date?
    public var artworkFile: String?

    public init(
        trackID: String? = nil,
        title: String = "",
        artist: String = "",
        duration: TimeInterval? = nil,
        position: TimeInterval = 0,
        isPlaying: Bool = false,
        platterDegrees: Double = 0,
        date: Date,
        playStartedAt: Date? = nil,
        artworkFile: String? = nil
    ) {
        self.trackID = trackID
        self.title = title
        self.artist = artist
        self.duration = duration
        self.position = position
        self.isPlaying = isPlaying
        self.platterDegrees = platterDegrees
        self.date = date
        self.playStartedAt = playStartedAt
        self.artworkFile = artworkFile
    }

    public static let nothingPlaying = PlaybackSnapshot(date: .init(timeIntervalSince1970: 0))

    /// Where the song is at `now`, extrapolating while playing.
    public func elapsed(at now: Date) -> TimeInterval {
        guard isPlaying else { return position }
        let t = position + max(0, now.timeIntervalSince(date))
        return duration.map { min($0, t) } ?? t
    }

    /// The platter angle at `now`; only playback time turns it.
    public func platter(at now: Date) -> Double {
        guard isPlaying else { return platterDegrees }
        return platterDegrees + Self.platterDegreesPerSecond * max(0, now.timeIntervalSince(date))
    }
}

/// One JSON file in the App Group container. A missing or corrupt file reads as nil.
public struct SnapshotStore: Sendable {
    public static let appGroup = "group.com.katsukiineko.monochrome"
    public static let snapshotFile = "playback-snapshot.json"
    /// The WidgetKit kind the app reloads and the extension registers.
    public static let widgetKind = "Turntable"

    public enum StoreError: Error, Equatable {
        case noContainer
    }

    public let directory: URL?

    public init(directory: URL?) {
        self.directory = directory
    }

    public var isAvailable: Bool { directory != nil }

    public static func shared() -> SnapshotStore {
        #if canImport(Darwin)
        let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        )
        return SnapshotStore(directory: url)
        #else
        return SnapshotStore(directory: nil)
        #endif
    }

    public func read() -> PlaybackSnapshot? {
        guard let url = directory?.appendingPathComponent(Self.snapshotFile),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(PlaybackSnapshot.self, from: data)
    }

    public func write(_ snapshot: PlaybackSnapshot) throws {
        guard let directory else { throw StoreError.noContainer }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: directory.appendingPathComponent(Self.snapshotFile), options: .atomic)
    }

    public func artworkURL(named name: String?) -> URL? {
        guard let directory, let name, !name.isEmpty else { return nil }
        return directory.appendingPathComponent(name)
    }

    public func writeArtwork(_ data: Data, named name: String) throws {
        guard let directory else { throw StoreError.noContainer }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }

    /// Deletes artwork files except `keeping`; leaves the snapshot file alone.
    public func pruneArtwork(keeping: [String]) {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return }
        let keep = Set(keeping)
        for file in files where file.hasPrefix("artwork-") && !keep.contains(file) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
    }
}
