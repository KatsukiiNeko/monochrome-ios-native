// PlaybackSession.swift: what survives an app restart, stored as JSON.
import Foundation

public struct PlaybackSession: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public static let maxQueueSize = 200

    public var schemaVersion: Int
    public var tracks: [Track]
    public var currentIndex: Int?
    public var position: Double
    public var isShuffled: Bool
    public var repeatMode: RepeatMode
    public var radioRunning: Bool
    public var savedAt: Date

    public init(
        tracks: [Track],
        currentIndex: Int?,
        position: Double,
        isShuffled: Bool,
        repeatMode: RepeatMode,
        radioRunning: Bool = false,
        savedAt: Date = .now
    ) {
        self.schemaVersion = Self.schemaVersion
        self.tracks = Array(tracks.prefix(Self.maxQueueSize))
        self.currentIndex = currentIndex.flatMap { min(max($0, 0), max(0, min(tracks.count, Self.maxQueueSize) - 1)) }
        self.position = max(0, position)
        self.isShuffled = isShuffled
        self.repeatMode = repeatMode
        self.radioRunning = radioRunning
        self.savedAt = savedAt
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, tracks, currentIndex, position, isShuffled, repeatMode, radioRunning, savedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.schemaVersion
        tracks = try c.decodeIfPresent([Track].self, forKey: .tracks) ?? []
        currentIndex = try c.decodeIfPresent(Int.self, forKey: .currentIndex)
        position = try c.decodeIfPresent(Double.self, forKey: .position) ?? 0
        isShuffled = try c.decodeIfPresent(Bool.self, forKey: .isShuffled) ?? false
        repeatMode = try c.decodeIfPresent(RepeatMode.self, forKey: .repeatMode) ?? .off
        radioRunning = try c.decodeIfPresent(Bool.self, forKey: .radioRunning) ?? false
        savedAt = try c.decodeIfPresent(Date.self, forKey: .savedAt) ?? .distantPast
    }
}

public struct PlaybackSessionStore: Sendable {
    private let file: JSONFileStore
    private let now: @Sendable () -> Date

    public init(fileURL: URL, now: @escaping @Sendable () -> Date = { .now }) {
        self.file = JSONFileStore(fileURL: fileURL, maxBytes: 4 * 1024 * 1024, now: now)
        self.now = now
    }

    public func load() -> PlaybackSession? {
        guard let session = file.read(PlaybackSession.self) else { return nil }
        guard session.schemaVersion == PlaybackSession.schemaVersion else { return nil }
        return session
    }

    public func save(_ session: PlaybackSession) {
        do { try file.write(session) } catch { }
    }

    public func clear() {
        try? FileManager.default.removeItem(at: file.fileURL)
    }
}