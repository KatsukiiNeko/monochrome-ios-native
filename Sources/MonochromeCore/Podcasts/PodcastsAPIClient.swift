// PodcastsAPIClient.swift: the public Apple podcast directory and the feeds it lists.
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Finds shows through the Apple podcast directory and reads their public RSS
/// feeds. Only plain HTTPS is used; no token or account is involved.
public struct PodcastsAPIClient: Sendable {
    public static let searchHost = "itunes.apple.com"
    public static let userAgent = TracksAPIClient.userAgent
    public static let feedByteLimit = PodcastFeedParser.maxFeedBytes

    public enum PodcastError: LocalizedError, Equatable {
        case emptyQuery
        case badResponse(Int)
        case missingFeed(String)
        case insecureFeed(String)
        case unreadableFeed(String)
        case feedTooLarge

        public var errorDescription: String? {
            switch self {
            case .emptyQuery:
                "Type a show name first."
            case .badResponse(let code):
                "The podcast directory answered with HTTP \(code)."
            case .missingFeed(let title):
                "“\(title)” does not list a public feed."
            case .insecureFeed(let title):
                "The feed for “\(title)” is not served over HTTPS."
            case .unreadableFeed(let title):
                "The feed for “\(title)” could not be read."
            case .feedTooLarge:
                "The feed is too large to read."
            }
        }
    }

    private let http: HTTPClient

    public init(http: HTTPClient = URLSessionHTTPClient()) {
        self.http = http
    }

    public func searchPodcasts(matching query: String, limit: Int = 20) async throws -> [RemotePodcast] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PodcastError.emptyQuery }
        var components = URLComponents()
        components.scheme = "https"
        components.host = Self.searchHost
        components.path = "/search"
        components.queryItems = [
            URLQueryItem(name: "term", value: trimmed),
            URLQueryItem(name: "media", value: "podcast"),
            URLQueryItem(name: "entity", value: "podcast"),
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 50))),
        ]
        guard let url = components.url else { throw PodcastError.emptyQuery }

        let request = Self.request(url)
        let (data, response) = try await http.data(for: request)
        guard response.statusCode == 200 else { throw PodcastError.badResponse(response.statusCode) }

        let envelope = try Self.decoder().decode(SearchEnvelope.self, from: data)
        return envelope.results.compactMap(Self.podcast(from:))
    }

    public func episodes(for podcast: RemotePodcast) async throws -> [PodcastEpisode] {
        guard let feedURL = podcast.feedURL else { throw PodcastError.missingFeed(podcast.title) }
        guard feedURL.scheme?.lowercased() == "https" else {
            throw PodcastError.insecureFeed(podcast.title)
        }
        var request = Self.request(feedURL)
        request.timeoutInterval = 20
        let (data, response) = try await http.data(for: request)
        guard response.statusCode == 200 else { throw PodcastError.badResponse(response.statusCode) }
        guard data.count <= Self.feedByteLimit else { throw PodcastError.feedTooLarge }
        guard let feed = PodcastFeedParser.parse(data) else {
            throw PodcastError.unreadableFeed(podcast.title)
        }
        let artwork = feed.artworkURL ?? podcast.artworkURL
        return feed.episodes.map { episode in
            var episode = episode
            if episode.artworkURL == nil { episode.artworkURL = artwork }
            return episode
        }
    }

    // MARK: - Request and decoding

    private static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, application/rss+xml;q=0.9, */*;q=0.5", forHTTPHeaderField: "Accept")
        return request
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        return decoder
    }

    /// The directory mixes show kinds and a show may lack a feed; both are
    /// dropped so every row keeps something playable.
    private static func podcast(from entry: SearchEntry) -> RemotePodcast? {
        guard entry.kind == "podcast" || (entry.kind == nil && entry.wrapperType == "track") else {
            return nil
        }
        guard let identifier = entry.collectionId else { return nil }
        let feed = entry.feedUrl.flatMap(URL.init(string:))
        return RemotePodcast(
            id: String(identifier),
            title: entry.collectionName ?? entry.trackName ?? "Untitled show",
            author: entry.artistName ?? "",
            feedURL: feed,
            artworkURL: entry.artworkUrl600.flatMap(URL.init(string:))
                ?? entry.artworkUrl100.flatMap(URL.init(string:)),
            genre: entry.primaryGenreName,
            episodeCount: entry.trackCount
        )
    }

    private struct SearchEnvelope: Decodable {
        let results: [SearchEntry]
    }

    private struct SearchEntry: Decodable {
        let wrapperType: String?
        let kind: String?
        let collectionId: Int?
        let collectionName: String?
        let trackName: String?
        let artistName: String?
        let feedUrl: String?
        let artworkUrl600: String?
        let artworkUrl100: String?
        let primaryGenreName: String?
        let trackCount: Int?
    }
}
