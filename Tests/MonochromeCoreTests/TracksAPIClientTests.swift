// TracksAPIClientTests.swift: host tests for catalog mapping and host failover with a fake HTTP client.
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import MonochromeCore

private final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URLRequest] = []

    func append(_ request: URLRequest) {
        lock.lock()
        storage.append(request)
        lock.unlock()
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private struct FakeHTTP: HTTPClient {
    let handler: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await handler(request)
    }
}

private enum FixtureError: Error {
    case missing(String)
}

private func fixture(_ name: String) throws -> Data {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
        throw FixtureError.missing(name)
    }
    return try Data(contentsOf: url)
}

private func http(_ request: URLRequest, _ status: Int) -> HTTPURLResponse {
    HTTPURLResponse(
        url: request.url!,
        statusCode: status,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "application/json"]
    )!
}

private let hostA = URL(string: "https://first.test")!
private let hostB = URL(string: "https://second.test")!

@Suite("TracksAPIClient")
struct TracksAPIClientTests {
    @Test func searchMapsTracksAndSendsTruthfulHeaders() async throws {
        let log = RequestLog()
        let data = try fixture("tracks-search")
        let client = TracksAPIClient(baseURLs: [hostA], http: FakeHTTP { request in
            log.append(request)
            return (data, http(request, 200))
        })

        let tracks = try await client.searchTracks(matching: "daft punk", limit: 2)

        #expect(tracks.count == 2)
        let first = try #require(tracks.first)
        #expect(first.id == "stream:155142491052445696")
        #expect(first.streamID == "155142491052445696")
        #expect(first.title == "Instant Crush (feat. Julian Casablancas)")
        #expect(first.artist == "Daft Punk, Julian Casablancas")
        #expect(first.provider == "monochrome")
        #expect(first.isStreaming)
        #expect(first.fileName.isEmpty)
        // Milliseconds in the payload, seconds in the model.
        #expect(first.durationSeconds == 337.56)
        #expect(first.artworkURL?.host == "tracks.monochrome.st")

        let request = try #require(log.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == TracksAPIClient.userAgent)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        let requestURL = try #require(request.url)
        let components = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
        #expect(components.path == "/search/tracks")
        #expect(components.queryItems?.contains(URLQueryItem(name: "q", value: "daft punk")) == true)
        #expect(components.queryItems?.contains(URLQueryItem(name: "limit", value: "2")) == true)
    }

    @Test func malformedEntriesAreDroppedOneByOne() async throws {
        let data = try fixture("tracks-malformed")
        let client = TracksAPIClient(baseURL: hostA, http: FakeHTTP { request in
            (data, http(request, 200))
        })

        let tracks = try await client.searchTracks(matching: "anything")

        // Numeric id and unplayable entry are dropped; the other two survive.
        #expect(tracks.map(\.title) == ["No duration", "Artist objects and bad duration"])
        #expect(tracks.first?.artist == "")
        #expect(tracks.first?.durationSeconds == nil)
        #expect(tracks.first?.artworkURL == nil) // http artwork is refused
        #expect(tracks.last?.artist == "Artist A, Artist B")
    }

    @Test func structurallyInvalidPayloadIsAnError() async {
        let client = TracksAPIClient(baseURL: hostA, http: FakeHTTP { request in
            (Data(#"{"tracks": "not an array"}"#.utf8), http(request, 200))
        })

        await #expect(throws: TracksAPIError.invalidPayload) {
            _ = try await client.searchTracks(matching: "anything")
        }
    }

    @Test func transportFailureFailsOverToNextHost() async throws {
        let log = RequestLog()
        let data = try fixture("tracks-search")
        let client = TracksAPIClient(baseURLs: [hostA, hostB], http: FakeHTTP { request in
            log.append(request)
            if request.url?.host == "first.test" { throw URLError(.cannotConnectToHost) }
            return (data, http(request, 200))
        })

        let tracks = try await client.searchTracks(matching: "daft punk")

        #expect(tracks.count == 2)
        #expect(log.requests.compactMap(\.url?.host) == ["first.test", "second.test"])
    }

    @Test func serverErrorFailsOverButClientErrorDoesNot() async throws {
        let data = try fixture("tracks-search")
        let log = RequestLog()
        let client = TracksAPIClient(baseURLs: [hostA, hostB], http: FakeHTTP { request in
            log.append(request)
            let status = request.url?.host == "first.test" ? 503 : 200
            return (status == 200 ? data : Data(), http(request, status))
        })
        let tracks = try await client.searchTracks(matching: "daft punk")
        #expect(tracks.count == 2)
        #expect(log.requests.count == 2)

        let single = RequestLog()
        let failing = TracksAPIClient(baseURLs: [hostA, hostB], http: FakeHTTP { request in
            single.append(request)
            return (Data(), http(request, 404))
        })
        await #expect(throws: TracksAPIError.httpStatus(404)) {
            _ = try await failing.searchTracks(matching: "daft punk")
        }
        #expect(single.requests.count == 1)
    }

    @Test func releaseDetailKeepsReleaseAsAlbum() async throws {
        let data = try fixture("release-detail")
        let client = TracksAPIClient(baseURL: hostA, http: FakeHTTP { request in
            (data, http(request, 200))
        })

        let detail = try await client.release(id: "155102851176075264")

        #expect(detail.release.title == "Discovery")
        #expect(detail.release.artist == "Daft Punk")
        #expect(detail.tracks.count == 3)
        #expect(detail.tracks.first?.album == "Discovery")
        #expect(detail.tracks.first?.durationSeconds == 320.357)
        #expect(detail.tracks.first?.isStreaming == true)
    }

    @Test func artistDetailMapsTopTracksAndReleases() async throws {
        let data = try fixture("artist-detail")
        let client = TracksAPIClient(baseURL: hostA, http: FakeHTTP { request in
            (data, http(request, 200))
        })

        let detail = try await client.artist(id: "153542153123926016")

        #expect(detail.artist.name == "Daft Punk")
        #expect(detail.topTracks.count == 2)
        #expect(detail.releases.count == 2)
        #expect(detail.topTracks.first?.streamID == "287206674229092352")
    }

    @Test func streamURLIsBuiltFromStreamID() async {
        let client = TracksAPIClient(baseURL: hostB)
        let track = Track(
            id: "stream:42",
            title: "Streamed",
            provider: "monochrome",
            streamID: "42"
        )

        let url = await client.streamURL(for: track)

        #expect(url?.absoluteString == "https://second.test/track/42")
        #expect(await client.streamURL(for: Track(title: "Local", fileName: "a.m4a")) == nil)
    }
}
