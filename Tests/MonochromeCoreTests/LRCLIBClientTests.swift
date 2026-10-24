// LRCLIBClientTests.swift: request shape, fallback, states and error mapping.
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import MonochromeCore

private enum MockOutcome: Sendable {
    case http(status: Int, body: Data, headers: [String: String])
    case failure(URLError.Code)
}

private actor MockHTTPClient: HTTPClient {
    private var outcomes: [MockOutcome]
    private(set) var requests: [URLRequest] = []

    init(_ outcomes: [MockOutcome]) {
        self.outcomes = outcomes
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !outcomes.isEmpty else { throw URLError(.cannotConnectToHost) }
        switch outcomes.removeFirst() {
        case .http(let status, let body, let headers):
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: status,
                    httpVersion: nil,
                    headerFields: headers
                  )
            else { throw URLError(.badServerResponse) }
            return (body, response)
        case .failure(let code):
            throw URLError(code)
        }
    }
}

@Suite("LRCLIBClient")
struct LRCLIBClientTests {
    private func query(
        title: String = "Synthetic Song",
        artist: String = "Synthetic Artist",
        duration: TimeInterval? = 200
    ) -> LyricsQuery {
        LyricsQuery(
            trackID: "track-1",
            title: title,
            artist: artist,
            album: "Synthetic Album",
            duration: duration
        )
    }

    private func record(
        track: String = "Synthetic Song",
        artist: String = "Synthetic Artist",
        duration: Double? = 200,
        instrumental: Bool = false,
        synced: String? = "[00:01.00]Synthetic first line\n[00:05.00]Synthetic second line",
        plain: String? = "Synthetic plain line"
    ) -> [String: Any] {
        var value: [String: Any] = [
            "id": 1,
            "trackName": track,
            "artistName": artist,
            "albumName": "Synthetic Album",
            "duration": duration ?? NSNull(),
            "instrumental": instrumental,
        ]
        value["syncedLyrics"] = synced ?? NSNull()
        value["plainLyrics"] = plain ?? NSNull()
        return value
    }

    private func data(_ value: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: value)) ?? Data()
    }

    private func ok(_ value: Any) -> MockOutcome {
        .http(status: 200, body: data(value), headers: [:])
    }

    @Test func exactLookupReturnsSyncedLinesAndSendsOnlyTrackMetadata() async throws {
        let http = MockHTTPClient([ok(record())])
        let client = LRCLIBClient(http: http, version: "1.2.3")

        let result = try await client.fetch(query())

        guard case .synced(let lines) = result.content else {
            Issue.record("expected synced lines")
            return
        }
        #expect(lines.map(\.text) == ["Synthetic first line", "Synthetic second line"])
        #expect(result.source == "LRCLIB")

        let requests = await http.requests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.url?.path == "/api/get")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Monochrome/1.2.3 (+https://github.com/KatsukiiNeko/monochrome-ios-native)")

        let items = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        let names = Set(items.map(\.name))
        #expect(names == ["track_name", "artist_name", "album_name", "duration"])
        #expect(items.first { $0.name == "duration" }?.value == "200")
        #expect(items.first { $0.name == "album_name" }?.value == "Synthetic Album")
    }

    @Test func aMissingExactRecordFallsBackToSearch() async throws {
        let http = MockHTTPClient([
            .http(status: 404, body: Data(), headers: [:]),
            ok([record(track: "Synthetic Song (Live)", duration: 200)]),
        ])
        let client = LRCLIBClient(http: http, version: "1.0")

        let result = try await client.fetch(query())

        guard case .synced = result.content else {
            Issue.record("expected a synced result from search")
            return
        }
        let requests = await http.requests
        #expect(requests.count == 2)
        #expect(requests.last?.url?.path == "/api/search")
        let items = URLComponents(
            url: try #require(requests.last?.url),
            resolvingAgainstBaseURL: false
        )?.queryItems ?? []
        #expect(Set(items.map(\.name)) == ["track_name", "artist_name"])
    }

    @Test func plainOnlyRecordsReturnPlainText() async throws {
        let client = LRCLIBClient(
            http: MockHTTPClient([ok(record(synced: nil, plain: "Synthetic plain line"))]),
            version: "1.0"
        )

        let result = try await client.fetch(query())

        #expect(result.content == .plain("Synthetic plain line"))
    }

    @Test func instrumentalRecordsReturnTheInstrumentalState() async throws {
        let client = LRCLIBClient(
            http: MockHTTPClient([ok(record(instrumental: true, synced: nil, plain: nil))]),
            version: "1.0"
        )

        let result = try await client.fetch(query())

        #expect(result.content == .instrumental)
    }

    @Test func malformedJSONIsAnInvalidResponse() async {
        let client = LRCLIBClient(
            http: MockHTTPClient([.http(status: 200, body: Data("not json".utf8), headers: [:])]),
            version: "1.0"
        )

        await #expect(throws: LyricsProviderError.invalidResponse) {
            _ = try await client.fetch(self.query())
        }
    }

    @Test func rateLimitsKeepRetryAfterAndDoNotFallBackToSearch() async {
        let http = MockHTTPClient([
            .http(status: 429, body: Data(), headers: ["Retry-After": "7"]),
        ])
        let client = LRCLIBClient(http: http, version: "1.0")

        await #expect(throws: LyricsProviderError.rateLimited(retryAfter: 7)) {
            _ = try await client.fetch(self.query())
        }
        #expect(await http.requests.count == 1)
    }

    @Test func timeoutsMapToATransientError() async {
        let client = LRCLIBClient(
            http: MockHTTPClient([.failure(.timedOut)]),
            version: "1.0"
        )

        await #expect(throws: LyricsProviderError.transient) {
            _ = try await client.fetch(self.query())
        }
    }

    @Test func aLostConnectionMapsToOffline() async {
        let client = LRCLIBClient(
            http: MockHTTPClient([.failure(.notConnectedToInternet)]),
            version: "1.0"
        )

        await #expect(throws: LyricsProviderError.offline) {
            _ = try await client.fetch(self.query())
        }
    }

    @Test func aWrongDurationFromTheExactLookupIsRejected() async throws {
        let http = MockHTTPClient([
            ok(record(duration: 220)),
            ok([record(duration: 201)]),
        ])
        let client = LRCLIBClient(http: http, version: "1.0")

        let result = try await client.fetch(query())

        guard case .synced = result.content else {
            Issue.record("expected the search result to be accepted")
            return
        }
        #expect(await http.requests.count == 2)
    }

    @Test func noMatchingRecordReturnsNotFound() async throws {
        let client = LRCLIBClient(
            http: MockHTTPClient([
                .http(status: 404, body: Data(), headers: [:]),
                ok([]),
            ]),
            version: "1.0"
        )

        let result = try await client.fetch(query())

        #expect(result.isNotFound)
    }

    @Test func aQueryWithoutDurationSkipsTheExactLookup() async throws {
        let http = MockHTTPClient([ok([record()])])
        let client = LRCLIBClient(http: http, version: "1.0")

        _ = try await client.fetch(query(duration: nil))

        let requests = await http.requests
        #expect(requests.count == 1)
        #expect(requests.first?.url?.path == "/api/search")
    }

    @Test func vietnameseMetadataIsEncodedAndSentAsGiven() async throws {
        let title = "Anh Là Thằng Tồi"
        let artist = "Nghệ Sĩ Thử Nghiệm"
        let http = MockHTTPClient([ok(record(track: title, artist: artist))])
        let client = LRCLIBClient(http: http, version: "1.0")

        _ = try await client.fetch(query(title: title, artist: artist))

        let requests = await http.requests
        let items = URLComponents(
            url: try #require(requests.first?.url),
            resolvingAgainstBaseURL: false
        )?.queryItems ?? []
        #expect(items.first { $0.name == "track_name" }?.value == title)
        #expect(items.first { $0.name == "artist_name" }?.value == artist)
    }
}
