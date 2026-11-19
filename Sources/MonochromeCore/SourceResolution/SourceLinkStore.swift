// SourceLinkStore.swift: which track in the other source is the same recording.
import Foundation

public enum SourceLinkState: String, Codable, Equatable, Sendable {
    /// Accepted by the matcher. Expires so a better copy can be found later.
    case confirmed
    /// Nothing acceptable was found. Retried after a day.
    case rejected
    /// The listener decided. Kept until cleared.
    case manual
}

/// One verdict about a pair of sources for a track. The requested side is
/// stored as provider plus id; the counterpart is stored whole so it can play
/// without another lookup. A rejected or overruled link has no counterpart.
public struct SourceLink: Codable, Equatable, Sendable {
    public static let positiveLifetime: TimeInterval = 30 * 24 * 60 * 60
    public static let negativeLifetime: TimeInterval = 24 * 60 * 60

    public var provider: String
    public var trackID: String
    public var counterpartProvider: String
    public var counterpart: Track?
    public var state: SourceLinkState
    public var method: MatchMethod
    public var confidence: Double
    public var updatedAt: Date

    public init(
        provider: String,
        trackID: String,
        counterpartProvider: String,
        counterpart: Track?,
        state: SourceLinkState,
        method: MatchMethod,
        confidence: Double,
        updatedAt: Date
    ) {
        self.provider = provider
        self.trackID = trackID
        self.counterpartProvider = counterpartProvider
        self.counterpart = counterpart
        self.state = state
        self.method = method
        self.confidence = confidence
        self.updatedAt = updatedAt
    }

    public static func key(provider: String, trackID: String, counterpartProvider: String) -> String {
        "\(provider)|\(trackID)|\(counterpartProvider)"
    }

    public var key: String {
        Self.key(provider: provider, trackID: trackID, counterpartProvider: counterpartProvider)
    }

    public func isFresh(at date: Date) -> Bool {
        switch state {
        case .manual: true
        case .confirmed: date.timeIntervalSince(updatedAt) < Self.positiveLifetime
        case .rejected: date.timeIntervalSince(updatedAt) < Self.negativeLifetime
        }
    }
}

/// One versioned JSON file. Stale links are dropped on save, the newest links
/// survive the cap, and the file stays out of backups.
public struct SourceLinkStore: Sendable {
    public static let schemaVersion = 1
    public static let maxLinks = 5000
    public static let maxBytes = 4 * 1024 * 1024

    public struct Content: Codable, Equatable, Sendable {
        public var schemaVersion: Int
        public var links: [SourceLink]

        public init(links: [SourceLink] = []) {
            self.schemaVersion = SourceLinkStore.schemaVersion
            self.links = links
        }

        private enum CodingKeys: String, CodingKey { case schemaVersion, links }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
                ?? SourceLinkStore.schemaVersion
            links = try container.decodeIfPresent([SourceLink].self, forKey: .links) ?? []
        }
    }

    private let file: JSONFileStore
    private let now: @Sendable () -> Date
    private let log: (@Sendable (String) -> Void)?

    public init(
        fileURL: URL,
        now: @escaping @Sendable () -> Date = { .now },
        log: (@Sendable (String) -> Void)? = nil
    ) {
        self.file = JSONFileStore(fileURL: fileURL, maxBytes: Self.maxBytes, now: now)
        self.now = now
        self.log = log
    }

    /// A fresh verdict, or nil when there is none.
    public func link(provider: String, trackID: String, counterpartProvider: String) -> SourceLink? {
        let key = SourceLink.key(
            provider: provider,
            trackID: trackID,
            counterpartProvider: counterpartProvider
        )
        return load().links.first { $0.key == key && $0.isFresh(at: now()) }
    }

    public func record(_ link: SourceLink) throws {
        var content = load()
        content.links.removeAll { $0.key == link.key }
        content.links.append(link)
        try save(content)
    }

    /// Clears the verdict for one pair, so the next play searches again.
    public func clear(provider: String, trackID: String, counterpartProvider: String) throws {
        var content = load()
        let key = SourceLink.key(
            provider: provider,
            trackID: trackID,
            counterpartProvider: counterpartProvider
        )
        content.links.removeAll { $0.key == key }
        try save(content)
    }

    private func load() -> Content {
        file.read(Content.self) ?? Content()
    }

    private func save(_ content: Content) throws {
        var trimmed = content
        trimmed.links = Self.trim(trimmed.links, at: now())
        try file.write(trimmed)
        excludeFromBackups()
    }

    /// Drops expired verdicts, then the oldest links above the cap.
    static func trim(_ links: [SourceLink], at date: Date, maxLinks: Int = maxLinks) -> [SourceLink] {
        let fresh = links.filter { $0.isFresh(at: date) }
        guard fresh.count > maxLinks else { return fresh }
        return Array(fresh.sorted { $0.updatedAt > $1.updatedAt }.prefix(maxLinks))
    }

    /// The link cache is a cache, not listener data, so it stays off backups.
    private func excludeFromBackups() {
        #if canImport(Darwin)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = file.fileURL
        try? url.setResourceValues(values)
        #endif
    }
}
