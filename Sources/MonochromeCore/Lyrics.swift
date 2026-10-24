// Lyrics.swift: provider-independent lyrics values and the current-track query.
import Foundation

public struct LyricLine: Codable, Equatable, Sendable {
    public var time: TimeInterval
    public var text: String

    public init(time: TimeInterval, text: String) {
        self.time = time
        self.text = text
    }
}

/// Everything sent to a lyrics provider, plus the app-local track id used for caching.
public struct LyricsQuery: Equatable, Sendable {
    public var trackID: String
    public var title: String
    public var artist: String
    public var album: String?
    public var duration: TimeInterval?

    public init(
        trackID: String,
        title: String,
        artist: String,
        album: String? = nil,
        duration: TimeInterval? = nil
    ) {
        self.trackID = trackID
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
    }

    /// A query without a title or artist is never sent.
    public var isQueryable: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public struct LyricsResult: Codable, Equatable, Sendable {
    public enum Content: Codable, Equatable, Sendable {
        case synced([LyricLine])
        case plain(String)
        case instrumental
        case notFound
    }

    public var content: Content
    /// Provider name shown in the sheet footer.
    public var source: String

    public init(content: Content, source: String) {
        self.content = content
        self.source = source
    }

    public var isNotFound: Bool {
        if case .notFound = content { return true }
        return false
    }
}

public protocol LyricsProviding: Sendable {
    var sourceName: String { get }
    func fetch(_ query: LyricsQuery) async throws -> LyricsResult
}

public enum LyricsProviderError: Error, Equatable, Sendable {
    /// The device has no usable connection; the cache may still answer.
    case offline
    /// A connection failed in a way that is worth one retry.
    case transient
    case rateLimited(retryAfter: TimeInterval?)
    case server(status: Int)
    case invalidResponse
    case notFound
}

extension LyricsProviderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .offline:
            "Lyrics are not available offline."
        case .transient:
            "The lyrics service could not be reached."
        case .rateLimited(let retryAfter):
            if let retryAfter, retryAfter > 0 {
                "The lyrics service is busy. Try again in \(Int(retryAfter.rounded(.up))) seconds."
            } else {
                "The lyrics service is busy. Try again later."
            }
        case .server:
            "The lyrics service returned an error."
        case .invalidResponse:
            "The lyrics service returned an unexpected response."
        case .notFound:
            "No lyrics were found for this track."
        }
    }
}
