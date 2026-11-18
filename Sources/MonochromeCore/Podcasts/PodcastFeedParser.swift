// PodcastFeedParser.swift: a tolerant reader for podcast RSS feeds.
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Reads the channel header and the audio episodes out of a podcast feed. The
/// feeds in the wild carry many namespaces, so every field is optional and a
/// bad episode is dropped instead of failing the whole feed.
public enum PodcastFeedParser {
    /// A feed bigger than this is treated as unreadable.
    public static let maxFeedBytes = 8 * 1024 * 1024
    /// The feed order is newest first, so the cap keeps the newest episodes.
    public static let maxEpisodes = 300
    /// Summaries longer than this are cut; they are only a list subtitle.
    public static let maxSummaryLength = 400

    public static func parse(_ data: Data, maxEpisodes: Int = maxEpisodes) -> PodcastFeed? {
        guard data.count <= maxFeedBytes else { return nil }
        let parser = XMLParser(data: data)
        let delegate = FeedDelegate(maxEpisodes: maxEpisodes)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else { return nil }
        return delegate.feed()
    }

    /// Accepts `90`, `4:40` and `1:02:03`; anything else is unknown.
    public static func duration(_ text: String) -> Double? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var seconds: Double = 0
        for part in parts {
            guard let value = Double(part.trimmingCharacters(in: .whitespaces)), value >= 0 else {
                return nil
            }
            seconds = seconds * 60 + value
        }
        return seconds
    }

    public static func date(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.date(from: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Feed descriptions are HTML; the list shows plain text only.
    public static func plainText(_ html: String) -> String {
        var text = ""
        var insideTag = false
        for character in html {
            if character == "<" {
                insideTag = true
            } else if character == ">" {
                insideTag = false
                text.append(" ")
            } else if !insideTag {
                text.append(character)
            }
        }
        let replacements = [
            "&nbsp;": " ", "&amp;": "&", "&quot;": "\"", "&#39;": "'",
            "&apos;": "'", "&lt;": "<", "&gt;": ">",
        ]
        for (entity, value) in replacements {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        return text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Collects the feed while `XMLParser` walks it. Prefix-qualified names such as
/// `itunes:duration` arrive verbatim because namespace processing is off.
private final class FeedDelegate: NSObject, XMLParserDelegate {
    private let maxEpisodes: Int

    private var channelTitle = ""
    private var channelAuthor: String?
    private var channelArtwork: URL?
    private var channelImageURL: URL?
    private var episodes: [PodcastEpisode] = []

    private var isInItem = false
    private var buffer = ""

    private var itemTitle = ""
    private var itemGUID: String?
    private var itemSummary: String?
    private var itemDescription: String?
    private var itemArtwork: URL?
    private var itemAudioURL: URL?
    private var itemIsAudio = true
    private var itemDuration: Double?
    private var itemDate: Date?

    init(maxEpisodes: Int) {
        self.maxEpisodes = maxEpisodes
    }

    func feed() -> PodcastFeed? {
        guard !channelTitle.isEmpty else { return nil }
        return PodcastFeed(
            title: channelTitle,
            author: channelAuthor,
            artworkURL: channelArtwork ?? channelImageURL,
            episodes: episodes
        )
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes: [String: String] = [:]
    ) {
        buffer = ""
        switch elementName {
        case "item":
            isInItem = true
            resetItem()
        case "enclosure":
            guard isInItem, let value = attributes["url"], let url = URL(string: value) else { return }
            if let type = attributes["type"], type.lowercased().hasPrefix("video") {
                itemIsAudio = false
            } else {
                itemAudioURL = url
            }
        case "itunes:image":
            let url = attributes["href"].flatMap(URL.init(string:))
            if isInItem { itemArtwork = url } else { channelArtwork = url }
        case "media:thumbnail":
            if !isInItem, channelArtwork == nil {
                channelArtwork = attributes["url"].flatMap(URL.init(string:))
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        buffer += String(decoding: CDATABlock, as: UTF8.self)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if isInItem {
            endItemElement(elementName, text: text)
        } else {
            endChannelElement(elementName, text: text)
        }
        buffer = ""
    }

    private func endChannelElement(_ name: String, text: String) {
        switch name {
        case "title" where channelTitle.isEmpty:
            channelTitle = text
        case "itunes:author" where channelAuthor == nil:
            channelAuthor = text.isEmpty ? nil : text
        case "url" where channelImageURL == nil:
            channelImageURL = httpsURL(text)
        default:
            break
        }
    }

    private func endItemElement(_ name: String, text: String) {
        switch name {
        case "title" where itemTitle.isEmpty:
            itemTitle = PodcastFeedParser.plainText(text)
        case "guid" where itemGUID == nil:
            itemGUID = text.isEmpty ? nil : text
        case "itunes:duration":
            itemDuration = PodcastFeedParser.duration(text)
        case "pubDate":
            itemDate = PodcastFeedParser.date(text)
        case "itunes:summary":
            itemSummary = text.isEmpty ? nil : text
        case "description", "content:encoded":
            if itemDescription == nil, !text.isEmpty { itemDescription = text }
        case "item":
            finishItem()
        default:
            break
        }
    }

    private func finishItem() {
        defer {
            isInItem = false
            resetItem()
        }
        guard itemIsAudio, let audioURL = itemAudioURL, audioURL.scheme == "https" else { return }
        guard episodes.count < maxEpisodes else { return }
        let summarySource = itemSummary ?? itemDescription
        episodes.append(PodcastEpisode(
            id: itemGUID ?? audioURL.absoluteString,
            title: itemTitle.isEmpty ? "Untitled episode" : itemTitle,
            audioURL: audioURL,
            durationSeconds: itemDuration,
            publishedAt: itemDate,
            summary: summarySource.map {
                String(PodcastFeedParser.plainText($0).prefix(PodcastFeedParser.maxSummaryLength))
            },
            artworkURL: itemArtwork
        ))
    }

    private func resetItem() {
        itemTitle = ""
        itemGUID = nil
        itemSummary = nil
        itemDescription = nil
        itemArtwork = nil
        itemAudioURL = nil
        itemIsAudio = true
        itemDuration = nil
        itemDate = nil
    }

    private func httpsURL(_ text: String) -> URL? {
        guard let url = URL(string: text), url.scheme == "https" else { return nil }
        return url
    }
}
