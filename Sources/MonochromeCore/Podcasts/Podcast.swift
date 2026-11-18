// Podcast.swift: the podcast show and episode models plus their track mapping.
import Foundation

/// A show from the Apple podcast directory.
public struct RemotePodcast: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var author: String
    /// The public RSS feed; nil when the directory lists none.
    public var feedURL: URL?
    public var artworkURL: URL?
    public var genre: String?
    public var episodeCount: Int?

    public init(
        id: String,
        title: String,
        author: String = "",
        feedURL: URL? = nil,
        artworkURL: URL? = nil,
        genre: String? = nil,
        episodeCount: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.feedURL = feedURL
        self.artworkURL = artworkURL
        self.genre = genre
        self.episodeCount = episodeCount
    }
}

public struct PodcastEpisode: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    /// The episode file itself; the app streams it, it never proxies it.
    public var audioURL: URL
    public var durationSeconds: Double?
    public var publishedAt: Date?
    public var summary: String?
    public var artworkURL: URL?

    public init(
        id: String,
        title: String,
        audioURL: URL,
        durationSeconds: Double? = nil,
        publishedAt: Date? = nil,
        summary: String? = nil,
        artworkURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.audioURL = audioURL
        self.durationSeconds = durationSeconds
        self.publishedAt = publishedAt
        self.summary = summary
        self.artworkURL = artworkURL
    }
}

public struct PodcastFeed: Equatable, Sendable {
    public var title: String
    public var author: String?
    public var artworkURL: URL?
    public var episodes: [PodcastEpisode]

    public init(
        title: String,
        author: String? = nil,
        artworkURL: URL? = nil,
        episodes: [PodcastEpisode] = []
    ) {
        self.title = title
        self.author = author
        self.artworkURL = artworkURL
        self.episodes = episodes
    }
}

extension PodcastEpisode {
    /// Provider value that marks an episode in the player queue.
    public static let provider = "podcast"

    /// Episodes play from their own HTTPS audio URL, so the URL travels in
    /// `streamID` and the resolver hands it straight to the engine.
    public func track(show: RemotePodcast) -> Track {
        Track(
            id: "podcast:\(id)",
            title: title,
            artist: show.author.isEmpty ? show.title : show.author,
            album: show.title,
            durationSeconds: durationSeconds,
            provider: Self.provider,
            streamID: audioURL.absoluteString,
            artworkURL: artworkURL ?? show.artworkURL
        )
    }
}
