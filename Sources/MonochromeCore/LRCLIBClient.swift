// LRCLIBClient.swift: token-free lyrics lookups against the documented LRCLIB API.
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Uses only the public endpoints from https://lrclib.net/docs:
/// `/api/get` for an exact lookup and `/api/search` as the fallback.
public struct LRCLIBClient: LyricsProviding {
    public let sourceName = "LRCLIB"
    private let http: any HTTPClient
    private let userAgent: String
    private let baseURL: URL

    public init(
        http: any HTTPClient = URLSessionHTTPClient(),
        version: String,
        baseURL: URL = URL(string: "https://lrclib.net")!
    ) {
        self.http = http
        self.userAgent = "Monochrome/\(Self.safeVersion(version)) (+https://github.com/KatsukiiNeko/monochrome-ios-native)"
        self.baseURL = baseURL
    }

    public func fetch(_ query: LyricsQuery) async throws -> LyricsResult {
        guard query.isQueryable else { throw LyricsProviderError.notFound }
        try Task.checkCancellation()

        if let record = try await exactLookup(query) {
            if let result = Self.result(from: record, source: sourceName) {
                return result
            }
        }
        try Task.checkCancellation()

        if let record = try await search(query),
           let result = Self.result(from: record, source: sourceName) {
            return result
        }
        return LyricsResult(content: .notFound, source: sourceName)
    }

    // MARK: - Endpoints

    private func exactLookup(_ query: LyricsQuery) async throws -> Record? {
        // The lookup only makes sense with a duration, and it is the value used
        // to reject a different release of the same title.
        guard let duration = query.duration, duration >= 1, duration <= 3_600 else {
            return nil
        }
        var items = [
            URLQueryItem(name: "track_name", value: query.title),
            URLQueryItem(name: "artist_name", value: query.artist),
            URLQueryItem(name: "duration", value: String(Int(duration.rounded()))),
        ]
        if let album = query.album, !album.isEmpty {
            items.append(URLQueryItem(name: "album_name", value: album))
        }

        let (data, response) = try await send(path: "api/get", items: items)
        switch response.statusCode {
        case 200:
            guard let record = try? JSONDecoder().decode(Record.self, from: data) else {
                throw LyricsProviderError.invalidResponse
            }
            let matched = LyricsMatcher.bestMatch(for: query, in: [record.candidate]) != nil
            return matched ? record : nil
        case 400, 404:
            return nil
        case 429:
            throw LyricsProviderError.rateLimited(retryAfter: retryAfter(response))
        default:
            throw LyricsProviderError.server(status: response.statusCode)
        }
    }

    private func search(_ query: LyricsQuery) async throws -> Record? {
        let items = [
            URLQueryItem(name: "track_name", value: query.title),
            URLQueryItem(name: "artist_name", value: query.artist),
        ]
        let (data, response) = try await send(path: "api/search", items: items)
        switch response.statusCode {
        case 200:
            guard let records = try? JSONDecoder().decode([Record].self, from: data) else {
                throw LyricsProviderError.invalidResponse
            }
            let pairs = records.map { ($0, $0.candidate) }
            guard let best = LyricsMatcher.bestMatch(for: query, in: pairs.map(\.1)) else {
                return nil
            }
            return pairs.first { $0.1 == best }?.0
        case 404:
            return nil
        case 429:
            throw LyricsProviderError.rateLimited(retryAfter: retryAfter(response))
        default:
            throw LyricsProviderError.server(status: response.statusCode)
        }
    }

    private func send(
        path: String,
        items: [URLQueryItem]
    ) async throws -> (Data, HTTPURLResponse) {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = items
        guard let url = components?.url else { throw LyricsProviderError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            return try await http.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            if Task.isCancelled { throw CancellationError() }
            switch error.code {
            case .cancelled:
                throw CancellationError()
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
                 .cannotConnectToHost, .dnsLookupFailed:
                throw LyricsProviderError.offline
            default:
                throw LyricsProviderError.transient
            }
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw LyricsProviderError.transient
        }
    }

    private func retryAfter(_ response: HTTPURLResponse) -> TimeInterval? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespaces), !raw.isEmpty
        else { return nil }
        if let seconds = TimeInterval(raw) { return seconds }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        guard let date = formatter.date(from: raw) else { return nil }
        return max(0, date.timeIntervalSinceNow)
    }

    // MARK: - Mapping

    private static func result(from record: Record, source: String) -> LyricsResult? {
        if record.instrumental == true {
            return LyricsResult(content: .instrumental, source: source)
        }
        if let synced = record.syncedLyrics, !synced.isEmpty {
            let lines = LRCParser.parse(synced)
            if !lines.isEmpty {
                return LyricsResult(content: .synced(lines), source: source)
            }
        }
        if let plain = record.plainLyrics,
           !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return LyricsResult(content: .plain(plain), source: source)
        }
        return nil
    }

    private static func safeVersion(_ version: String) -> String {
        let allowed = version.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == "." || $0 == "-"
        }
        let value = String(String.UnicodeScalarView(allowed))
        return value.isEmpty ? "0.0.0" : value
    }

    private struct Record: Decodable {
        var id: Int?
        var trackName: String?
        var artistName: String?
        var albumName: String?
        var duration: Double?
        var instrumental: Bool?
        var plainLyrics: String?
        var syncedLyrics: String?
        var hasWordSync: Bool?

        var candidate: LyricsCandidate {
            LyricsCandidate(
                trackName: trackName ?? "",
                artistName: artistName ?? "",
                albumName: albumName,
                duration: duration,
                hasSyncedLyrics: !(syncedLyrics ?? "").isEmpty,
                hasPlainLyrics: !(plainLyrics ?? "").isEmpty,
                instrumental: instrumental == true
            )
        }
    }
}
