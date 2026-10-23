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

    public init(artist: RemoteArtist, topTracks: [Track], releases: [RemoteRelease]) {
        self.artist = artist
        self.topTracks = topTracks
        self.releases = releases
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
    public static let defaultBaseURL = URL(string: "https://tracks.monochrome.st")!
    /// Truthful identity: we are not the website and do not claim to be.
    public static let userAgent = "MonochromeNative/1.0 (iOS; independent client)"

    public let baseURLs: [URL]
    private let http: any HTTPClient
    private var unhealthy: Set<String> = []

    public init(baseURLs: [URL], http: any HTTPClient = URLSessionHTTPClient()) {
        self.baseURLs = baseURLs
        self.http = http
    }

    public init(baseURL: URL = TracksAPIClient.defaultBaseURL, http: any HTTPClient = URLSessionHTTPClient()) {
        self.init(baseURLs: [baseURL], http: http)
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
        return RemoteArtistDetail(artist: artist, topTracks: tracks, releases: releases)
    }

    // MARK: - Streams

    /// Built at play time and never persisted: stream URLs are not part of a track's saved form.
    public func streamURL(for track: Track) -> URL? {
        guard let streamID = track.streamID, !streamID.isEmpty else { return nil }
        guard let base = preferredBaseURL else { return nil }
        return Self.url(path: "track/\(streamID)", on: base)
    }

    // MARK: - Transport

    private var preferredBaseURL: URL? {
        baseURLs.first { !unhealthy.contains($0.absoluteString) } ?? baseURLs.first
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

    /// Tries healthy hosts first, then the rest, and remembers which hosts just failed.
    private func get(path: String, query: [URLQueryItem] = []) async throws -> Data {
        let healthy = baseURLs.filter { !unhealthy.contains($0.absoluteString) }
        let failing = baseURLs.filter { unhealthy.contains($0.absoluteString) }
        var lastFailure = TracksAPIError.invalidPayload

        for base in healthy + failing {
            guard let url = Self.url(path: path, query: query, on: base) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

            do {
                let (data, response) = try await http.data(for: request)
                if (200..<300).contains(response.statusCode) {
                    unhealthy.remove(base.absoluteString)
                    return data
                }
                // A 4xx is about the request, not the host: retrying elsewhere cannot help.
                if response.statusCode == 429 || response.statusCode >= 500 {
                    unhealthy.insert(base.absoluteString)
                    lastFailure = .httpStatus(response.statusCode)
                    continue
                }
                throw TracksAPIError.httpStatus(response.statusCode)
            } catch let error as TracksAPIError {
                throw error
            } catch {
                unhealthy.insert(base.absoluteString)
                lastFailure = .unavailable(error.localizedDescription)
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
        let names = (artistNames?.isEmpty == false ? artistNames! : (artists ?? []).compactMap(\.name))
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
        let names = (artistNames?.isEmpty == false ? artistNames! : (artists ?? []).compactMap(\.name))
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
    var topTracks: [TrackDTO]?
    var releases: [ReleaseDTO]?

    private enum CodingKeys: String, CodingKey {
        case artistID = "artistId", id, name, avatar, topTracks, releases
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        artistID = try? container.decodeIfPresent(String.self, forKey: .artistID)
        id = try? container.decodeIfPresent(String.self, forKey: .id)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        avatar = try? container.decodeIfPresent(String.self, forKey: .avatar)
        topTracks = try? container.decodeIfPresent([TrackDTO].self, forKey: .topTracks)
        releases = try? container.decodeIfPresent([ReleaseDTO].self, forKey: .releases)
    }

    var artist: RemoteArtist? {
        guard let identifier = artistID ?? id, !identifier.isEmpty,
              let name, !name.isEmpty else { return nil }
        return RemoteArtist(id: identifier, name: name, avatarURL: TracksAPIClient.httpsURL(avatar))
    }
}

extension TracksAPIClient {
    /// Artwork must stay HTTPS: the app ships no ATS exception.
    static func httpsURL(_ string: String?) -> URL? {
        guard let string, let url = URL(string: string), url.scheme == "https" else { return nil }
        return url
    }
}
