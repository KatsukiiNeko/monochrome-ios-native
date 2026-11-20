// TracksAPIClient.swift: typed client for the public tracks catalog the web app uses.
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct RemoteRelease: Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var artist: String
    public var artworkURL: URL?
    public var releaseDate: String?
    public var trackCount: Int?

    public init(
        id: String,
        title: String,
        artist: String = "",
        artworkURL: URL? = nil,
        releaseDate: String? = nil,
        trackCount: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.artworkURL = artworkURL
        self.releaseDate = releaseDate
        self.trackCount = trackCount
    }
}

public struct RemoteArtist: Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var avatarURL: URL?

    public init(id: String, name: String, avatarURL: URL? = nil) {
        self.id = id
        self.name = name
        self.avatarURL = avatarURL
    }
}

public struct RemoteReleaseDetail: Equatable, Sendable {
    public var release: RemoteRelease
    public var tracks: [Track]

    public init(release: RemoteRelease, tracks: [Track]) {
        self.release = release
        self.tracks = tracks
    }
}

public struct RemoteArtistDetail: Equatable, Sendable {
    public var artist: RemoteArtist
    public var topTracks: [Track]
    public var releases: [RemoteRelease]
    /// Biography text from the catalog; nil when the host has none.
    public var biography: String?
    /// HTTPS-only outbound link (e.g. a link-in-bio service) and social pages.
    public var externalLink: URL?
    public var socialLinks: [URL]

    public init(
        artist: RemoteArtist,
        topTracks: [Track],
        releases: [RemoteRelease],
        biography: String? = nil,
        externalLink: URL? = nil,
        socialLinks: [URL] = []
    ) {
        self.artist = artist
        self.topTracks = topTracks
        self.releases = releases
        self.biography = biography
        self.externalLink = externalLink
        self.socialLinks = socialLinks
    }
}

public enum TracksAPIError: LocalizedError, Equatable {
    case notConfigured
    case httpStatus(Int)
    case unavailable(String)
    case invalidPayload

    public var errorDescription: String? {
        switch self {
        case .notConfigured: "The endpoint is switched off. Enable it in Settings to use the catalog."
        case .httpStatus(let code): "The music service answered with HTTP \(code)."
        case .unavailable(let reason): "The music service is unreachable. \(reason)"
        case .invalidPayload: "The music service returned data this app cannot read."
        }
    }
}

/// Actor because the in-session host health is shared mutable state.
public actor TracksAPIClient {
    public static let defaultBaseURL = StreamingSettings.defaultBaseURL
    /// Truthful identity: we are not the website and do not claim to be.
    public static let userAgent = "MonochromeNative/1.0 (iOS; independent client)"

    public let baseURLs: [URL]
    private let http: any HTTPClient
    private let now: @Sendable () -> Date
    private var cooldowns = HostCooldowns()

    public init(
        baseURLs: [URL],
        http: any HTTPClient = URLSessionHTTPClient(),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.baseURLs = baseURLs
        self.http = http
        self.now = now
    }

    public init(
        baseURL: URL = TracksAPIClient.defaultBaseURL,
        http: any HTTPClient = URLSessionHTTPClient(),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.init(baseURLs: [baseURL], http: http, now: now)
    }

    // MARK: - Catalog

    public func searchTracks(matching query: String, limit: Int = 25) async throws -> [Track] {
        let data = try await get(path: "search/tracks", query: Self.query(query, limit))
        let payload = try decode(TrackSearchPayload.self, from: data)
        return payload.tracks.compactMap { $0.track(album: "") }
    }

    public func searchReleases(matching query: String, limit: Int = 20) async throws -> [RemoteRelease] {
        let data = try await get(path: "search/releases", query: Self.query(query, limit))
        let payload = try decode(ReleaseSearchPayload.self, from: data)
        return payload.releases.compactMap(\.release)
    }

    public func searchArtists(matching query: String, limit: Int = 20) async throws -> [RemoteArtist] {
        let data = try await get(path: "search/artists", query: Self.query(query, limit))
        let payload = try decode(ArtistSearchPayload.self, from: data)
        return payload.artists.compactMap(\.artist)
    }

    public func release(id: String) async throws -> RemoteReleaseDetail {
        let data = try await get(path: "releases/\(id)")
        let payload = try decode(ReleaseDTO.self, from: data)
        guard let release = payload.release else { throw TracksAPIError.invalidPayload }
        let tracks = (payload.tracks ?? []).compactMap { $0.track(album: release.title) }
        return RemoteReleaseDetail(release: release, tracks: tracks)
    }

    public func artist(id: String) async throws -> RemoteArtistDetail {
        let data = try await get(path: "artists/\(id)")
        let payload = try decode(ArtistDTO.self, from: data)
        guard let artist = payload.artist else { throw TracksAPIError.invalidPayload }
        let tracks = (payload.topTracks ?? []).compactMap { $0.track(album: "") }
        let releases = (payload.releases ?? []).compactMap(\.release)
        return RemoteArtistDetail(
            artist: artist,
            topTracks: tracks,
            releases: releases,
            biography: payload.biographyText,
            externalLink: payload.externalLinkURL,
            socialLinks: payload.socialLinkURLs
        )
    }

    // MARK: - Streams

    /// Built at play time and never persisted: stream URLs are not part of a track's saved form.
    public func streamURL(for track: Track) -> URL? {
        guard let streamID = track.streamID, !streamID.isEmpty else { return nil }
        guard let base = orderedHosts().first else { return nil }
        return Self.url(path: "track/\(streamID)", on: base)
    }

    // MARK: - Transport

    /// Configured order, with hosts in cooldown moved behind the healthy ones.
    private func orderedHosts() -> [URL] {
        let stamp = now()
        let ready = baseURLs.filter { !cooldowns.isCoolingDown($0, at: stamp) }
        let cooling = baseURLs.filter { cooldowns.isCoolingDown($0, at: stamp) }
        return ready + cooling
    }

    private static func query(_ text: String, _ limit: Int) -> [URLQueryItem] {
        [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "limit", value: String(max(1, min(limit, 50)))),
        ]
    }

    private static func url(path: String, query: [URLQueryItem] = [], on base: URL) -> URL? {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        var basePath = components.path
        while basePath.hasSuffix("/") { basePath.removeLast() }
        components.path = basePath + "/" + path
        if !query.isEmpty { components.queryItems = query }
        return components.url
    }

    /// At most one cross-host retry per request. Network errors, 5xx and a 429
    /// with Retry-After rotate; any other 4xx stops at once because it describes
    /// the request, not the host.
    private func get(path: String, query: [URLQueryItem] = []) async throws -> Data {
        let ordered = orderedHosts()
        var attempts = 0
        var lastFailure = TracksAPIError.invalidPayload

        for base in ordered {
            guard attempts < 2 else { break }
            guard let url = Self.url(path: path, query: query, on: base) else { continue }
            attempts += 1
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

            do {
                let (data, response) = try await http.data(for: request)
                let status = response.statusCode
                if (200..<300).contains(status) {
                    cooldowns.reset(base)
                    return data
                }
                if status == 429 {
                    // Waiting out a rate limit needs a stated delay; without one
                    // the request fails instead of hammering another host.
                    guard let retryAfter = HostCooldowns.retryAfter(from: response, at: now()) else {
                        throw TracksAPIError.httpStatus(429)
                    }
                    cooldowns.penalize(base, at: now(), minimum: retryAfter)
                    lastFailure = .httpStatus(429)
                    continue
                }
                if status >= 500 {
                    cooldowns.penalize(base, at: now())
                    lastFailure = .httpStatus(status)
                    continue
                }
                throw TracksAPIError.httpStatus(status)
            } catch let error as TracksAPIError {
                throw error
            } catch {
                cooldowns.penalize(base, at: now())
                // A transport failure is reported by class, not as the opaque
                // NSURLError description the system would print.
                lastFailure = .unavailable(
                    TransferFailure.classify(error).errorDescription ?? error.localizedDescription
                )
            }
        }
        throw lastFailure
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw TracksAPIError.invalidPayload
        }
    }
}

// MARK: - Wire formats

// Every field is optional on purpose: the catalog is external data and one missing
// key must not throw away a whole search result.
private struct TrackSearchPayload: Decodable {
    var tracks: [TrackDTO]
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tracks = try container.decode([TrackDTO].self, forKey: .tracks)
    }
    private enum CodingKeys: String, CodingKey { case tracks }
}

private struct ReleaseSearchPayload: Decodable {
    var releases: [ReleaseDTO]
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        releases = try container.decode([ReleaseDTO].self, forKey: .releases)
    }
    private enum CodingKeys: String, CodingKey { case releases }
}

private struct ArtistSearchPayload: Decodable {
    var artists: [ArtistDTO]
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        artists = try container.decode([ArtistDTO].self, forKey: .artists)
    }
    private enum CodingKeys: String, CodingKey { case artists }
}

private struct ArtistRefDTO: Decodable {
    var name: String?
}

/// Prefers the flat name list, falling back to the nested artist objects.
private func artistNameList(_ names: [String]?, fallback artists: [ArtistRefDTO]?) -> [String] {
    if let names, !names.isEmpty { return names }
    return (artists ?? []).compactMap(\.name)
}

private struct TrackDTO: Decodable {
    var trackID: String?
    var title: String?
    var artistNames: [String]?
    var artists: [ArtistRefDTO]?
    var artwork: String?
    var duration: Double?
    var playable: Bool?

    private enum CodingKeys: String, CodingKey {
        case trackID = "trackId", title, artistNames, artists, artwork, duration, playable
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        trackID = try? container.decodeIfPresent(String.self, forKey: .trackID)
        title = try? container.decodeIfPresent(String.self, forKey: .title)
        artistNames = try? container.decodeIfPresent([String].self, forKey: .artistNames)
        artists = try? container.decodeIfPresent([ArtistRefDTO].self, forKey: .artists)
        artwork = try? container.decodeIfPresent(String.self, forKey: .artwork)
        duration = try? container.decodeIfPresent(Double.self, forKey: .duration)
        playable = try? container.decodeIfPresent(Bool.self, forKey: .playable)
    }

    func track(album: String) -> Track? {
        guard let trackID, !trackID.isEmpty, let title, !title.isEmpty else { return nil }
        // Unplayable entries would be dead rows in the UI.
        guard playable != false else { return nil }
        let names = artistNameList(artistNames, fallback: artists)
        return Track(
            id: Track.remoteIDPrefix + trackID,
            title: title,
            artist: names.joined(separator: ", "),
            album: album,
            // The API reports milliseconds.
            durationSeconds: duration.map { $0 / 1000 },
            provider: "monochrome",
            streamID: trackID,
            artworkURL: TracksAPIClient.httpsURL(artwork),
            // This endpoint serves the lossless tier for every track; the response
            // carries no quality field, so the tier is a property of the client.
            audioQuality: .lossless
        )
    }
}

private struct ReleaseDTO: Decodable {
    var releaseID: String?
    var title: String?
    var artistNames: [String]?
    var artists: [ArtistRefDTO]?
    var artwork: String?
    var releaseDate: String?
    var trackCount: Int?
    var tracks: [TrackDTO]?

    private enum CodingKeys: String, CodingKey {
        case releaseID = "releaseId", title, artistNames, artists, artwork
        case releaseDate, trackCount, tracks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        releaseID = try? container.decodeIfPresent(String.self, forKey: .releaseID)
        title = try? container.decodeIfPresent(String.self, forKey: .title)
        artistNames = try? container.decodeIfPresent([String].self, forKey: .artistNames)
        artists = try? container.decodeIfPresent([ArtistRefDTO].self, forKey: .artists)
        artwork = try? container.decodeIfPresent(String.self, forKey: .artwork)
        releaseDate = try? container.decodeIfPresent(String.self, forKey: .releaseDate)
        trackCount = try? container.decodeIfPresent(Int.self, forKey: .trackCount)
        tracks = try? container.decodeIfPresent([TrackDTO].self, forKey: .tracks)
    }

    var release: RemoteRelease? {
        guard let releaseID, !releaseID.isEmpty, let title, !title.isEmpty else { return nil }
        let names = artistNameList(artistNames, fallback: artists)
        return RemoteRelease(
            id: releaseID,
            title: title,
            artist: names.joined(separator: ", "),
            artworkURL: TracksAPIClient.httpsURL(artwork),
            releaseDate: releaseDate,
            trackCount: trackCount ?? tracks?.count
        )
    }
}

private struct ArtistDTO: Decodable {
    var artistID: String?
    var id: String?
    var name: String?
    var avatar: String?
    var bio: String?
    var biography: String?
    var externalLink: String?
    var socialLinks: [String]?
    var topTracks: [TrackDTO]?
    var releases: [ReleaseDTO]?

    private enum CodingKeys: String, CodingKey {
        case artistID = "artistId", id, name, avatar, bio, biography, externalLink, socialLinks, topTracks, releases
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        artistID = try? container.decodeIfPresent(String.self, forKey: .artistID)
        id = try? container.decodeIfPresent(String.self, forKey: .id)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        avatar = try? container.decodeIfPresent(String.self, forKey: .avatar)
        bio = try? container.decodeIfPresent(String.self, forKey: .bio)
        biography = try? container.decodeIfPresent(String.self, forKey: .biography)
        externalLink = try? container.decodeIfPresent(String.self, forKey: .externalLink)
        socialLinks = try? container.decodeIfPresent([String].self, forKey: .socialLinks)
        topTracks = try? container.decodeIfPresent([TrackDTO].self, forKey: .topTracks)
        releases = try? container.decodeIfPresent([ReleaseDTO].self, forKey: .releases)
    }

    var artist: RemoteArtist? {
        guard let identifier = artistID ?? id, !identifier.isEmpty,
              let name, !name.isEmpty else { return nil }
        return RemoteArtist(id: identifier, name: name, avatarURL: TracksAPIClient.httpsURL(avatar))
    }

    /// `bio` and `biography` are aliases on the endpoint; blank counts as none.
    var biographyText: String? {
        for candidate in [bio, biography] {
            if let candidate {
                let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    var externalLinkURL: URL? {
        TracksAPIClient.httpsURL(externalLink)
    }

    /// HTTPS-only, deduplicated, non-blank entries.
    var socialLinkURLs: [URL] {
        let seen = Set((socialLinks ?? []).compactMap { TracksAPIClient.httpsURL($0) })
        return seen.sorted { $0.absoluteString < $1.absoluteString }
    }
}

extension TracksAPIClient {
    /// Artwork must stay HTTPS: the app ships no ATS exception.
    static func httpsURL(_ string: String?) -> URL? {
        guard let string, let url = URL(string: string), url.scheme == "https" else { return nil }
        return url
    }
}
