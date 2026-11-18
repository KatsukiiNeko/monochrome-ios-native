// PodcastTests.swift: the feed parser, the directory client and the episode track mapping.
import Foundation
import Testing
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MonochromeCore

private func fixture(_ name: String, _ ext: String) throws -> Data {
    let url = try #require(
        Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures")
    )
    return try Data(contentsOf: url)
}

private struct StubHTTP: HTTPClient {
    var status = 200
    var data: Data = Data()

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

private let show = RemotePodcast(
    id: "121493675",
    title: "NPR News Now",
    author: "NPR",
    feedURL: URL(string: "https://feeds.npr.org/500005/podcast.xml"),
    artworkURL: URL(string: "https://media.npr.org/show.jpg")
)

@Suite("Podcast feed")
struct PodcastFeedTests {
    @Test("a real feed yields the channel and its audio episodes")
    func parsesRealFeed() throws {
        let feed = try #require(PodcastFeedParser.parse(try fixture("podcast-feed", "xml")))

        #expect(feed.title == "NPR News Now")
        #expect(feed.author == "NPR")
        #expect(feed.artworkURL?.scheme == "https")
        #expect(feed.episodes.count == 2)

        let first = try #require(feed.episodes.first)
        #expect(first.title.contains("November 17"))
        #expect(first.audioURL.scheme == "https")
        #expect(first.durationSeconds == 280)
        #expect(first.publishedAt != nil)
        #expect(first.summary?.contains("<") == false)
        #expect(first.id.hasPrefix("8f9aa60a"))
    }

    @Test("durations accept seconds, minutes and hours")
    func durationFormats() {
        #expect(PodcastFeedParser.duration("280") == 280)
        #expect(PodcastFeedParser.duration("4:40") == 280)
        #expect(PodcastFeedParser.duration("1:02:03") == 3723)
        #expect(PodcastFeedParser.duration("") == nil)
        #expect(PodcastFeedParser.duration("soon") == nil)
        #expect(PodcastFeedParser.duration("1:2:3:4") == nil)
    }

    @Test("summaries lose tags and entities")
    func plainText() {
        let html = "<p>Hello&nbsp;<b>there</b> &amp; welcome</p>"
        #expect(PodcastFeedParser.plainText(html) == "Hello there & welcome")
    }

    @Test("a feed without a channel title is unreadable")
    func rejectsUntitledFeed() {
        let xml = "<rss><channel><item><title>x</title></item></channel></rss>"
        #expect(PodcastFeedParser.parse(Data(xml.utf8)) == nil)
    }

    @Test("episodes without an HTTPS audio file are dropped")
    func dropsUnplayableEpisodes() {
        let xml = """
        <?xml version="1.0"?>
        <rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"><channel>
          <title>Show</title>
          <item><title>Video</title>
            <enclosure url="https://example.com/a.mp3" type="video/mp4"/></item>
          <item><title>Insecure</title>
            <enclosure url="http://example.com/b.mp3" type="audio/mpeg"/></item>
          <item><title>Good</title>
            <enclosure url="https://example.com/c.mp3" type="audio/mpeg"/>
            <itunes:duration>1:00</itunes:duration></item>
        </channel></rss>
        """
        let feed = PodcastFeedParser.parse(Data(xml.utf8))
        #expect(feed?.episodes.map(\.title) == ["Good"])
    }

    @Test("the episode cap keeps the newest entries")
    func episodeCap() {
        let items = (0..<5).map { index in
            "<item><title>E\(index)</title><enclosure url=\"https://example.com/\(index).mp3\" type=\"audio/mpeg\"/></item>"
        }.joined()
        let xml = "<rss><channel><title>Show</title>\(items)</channel></rss>"
        let feed = PodcastFeedParser.parse(Data(xml.utf8), maxEpisodes: 2)
        #expect(feed?.episodes.map(\.title) == ["E0", "E1"])
    }

    @Test("an oversized feed is refused before parsing")
    func rejectsOversizedFeed() {
        let data = Data(count: PodcastFeedParser.maxFeedBytes + 1)
        #expect(PodcastFeedParser.parse(data) == nil)
    }
}

@Suite("Podcast directory")
struct PodcastDirectoryTests {
    @Test("search keeps shows and drops other kinds")
    func searchFilters() async throws {
        let client = PodcastsAPIClient(http: StubHTTP(data: try fixture("podcast-search", "json")))
        let shows = try await client.searchPodcasts(matching: " news ")

        #expect(shows.map(\.title) == ["NPR News Now", "No Feed"])
        let first = try #require(shows.first)
        #expect(first.feedURL?.scheme == "https")
        #expect(first.artworkURL?.absoluteString.contains("artworkUrl") == false)
        #expect(first.genre == "News")
        #expect(first.episodeCount == 1000)
        #expect(shows.last?.feedURL == nil)
    }

    @Test("an empty query is refused without a request")
    func emptyQuery() async {
        let client = PodcastsAPIClient(http: StubHTTP())
        await #expect(throws: PodcastsAPIClient.PodcastError.emptyQuery) {
            try await client.searchPodcasts(matching: "  ")
        }
    }

    @Test("a failing directory answers with a readable error")
    func searchFailure() async throws {
        let client = PodcastsAPIClient(
            http: StubHTTP(status: 503, data: try fixture("podcast-search", "json"))
        )
        await #expect(throws: PodcastsAPIClient.PodcastError.badResponse(503)) {
            try await client.searchPodcasts(matching: "news")
        }
    }

    @Test("episodes come from the feed with the show artwork as a fallback")
    func loadsEpisodes() async throws {
        let client = PodcastsAPIClient(http: StubHTTP(data: try fixture("podcast-feed", "xml")))
        let episodes = try await client.episodes(for: show)

        #expect(episodes.count == 2)
        #expect(episodes.allSatisfy { $0.audioURL.scheme == "https" })
        #expect(episodes.allSatisfy { $0.artworkURL != nil })
    }

    @Test("a show without a feed is refused")
    func missingFeed() async {
        let client = PodcastsAPIClient(http: StubHTTP())
        var feedless = show
        feedless.feedURL = nil
        await #expect(throws: PodcastsAPIClient.PodcastError.missingFeed(show.title)) {
            try await client.episodes(for: feedless)
        }
    }

    @Test("an HTTP feed is refused instead of downgraded")
    func insecureFeed() async {
        let client = PodcastsAPIClient(http: StubHTTP())
        var insecure = show
        insecure.feedURL = URL(string: "http://feeds.npr.org/500005/podcast.xml")
        await #expect(throws: PodcastsAPIClient.PodcastError.insecureFeed(show.title)) {
            try await client.episodes(for: insecure)
        }
    }

    @Test("garbage in a feed is a readable error")
    func unreadableFeed() async throws {
        let client = PodcastsAPIClient(http: StubHTTP(data: Data("not xml".utf8)))
        await #expect(throws: PodcastsAPIClient.PodcastError.unreadableFeed(show.title)) {
            try await client.episodes(for: show)
        }
    }
}

@Suite("Podcast playback")
struct PodcastPlaybackTests {
    private var episode: PodcastEpisode {
        PodcastEpisode(
            id: "guid-1",
            title: "Episode one",
            audioURL: URL(string: "https://example.com/one.mp3")!,
            durationSeconds: 1800,
            artworkURL: nil
        )
    }

    @Test("an episode becomes a streamable track of its show")
    func trackMapping() {
        let track = episode.track(show: show)

        #expect(track.provider == PodcastEpisode.provider)
        #expect(track.id == "podcast:guid-1")
        #expect(track.album == show.title)
        #expect(track.artist == show.author)
        #expect(track.durationSeconds == 1800)
        #expect(track.streamID?.hasPrefix("https://") == true)
        #expect(track.artworkURL == show.artworkURL)
        #expect(track.source == .podcast)
        #expect(track.source.supportsDownloads == false)
    }

    @Test("the resolver plays the episode URL directly")
    func resolverUsesTheEpisodeURL() async throws {
        let resolver = DefaultTrackResolver(localDirectory: URL(fileURLWithPath: "/tmp"))
        let track = episode.track(show: show)

        let url = try await resolver.url(for: track)
        #expect(url == episode.audioURL)
        let type = await resolver.contentType(for: track)
        #expect(type == nil)
    }

    @Test("the resolver refuses an insecure episode URL")
    func resolverRejectsHTTP() async {
        let resolver = DefaultTrackResolver(localDirectory: URL(fileURLWithPath: "/tmp"))
        var insecure = episode
        insecure.audioURL = URL(string: "http://example.com/one.mp3")!
        let track = insecure.track(show: show)

        await #expect(throws: TrackResolutionError.notStreamable(track.title)) {
            try await resolver.url(for: track)
        }
    }

    @Test("the resolver still labels catalog streams as FLAC")
    func resolverLabelsCatalogStreams() async throws {
        let resolver = DefaultTrackResolver(localDirectory: URL(fileURLWithPath: "/tmp"))
        let track = Track(title: "Song", provider: "monochrome", streamID: "abc")

        let type = await resolver.contentType(for: track)
        #expect(type == DefaultTrackResolver.streamContentType)
    }
}
