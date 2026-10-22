// LiveTracksAPITests.swift: opt-in checks against the real catalog; skipped unless MONOCHROME_LIVE=1.
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import MonochromeCore

@Suite("Live tracks API", .enabled(if: ProcessInfo.processInfo.environment["MONOCHROME_LIVE"] == "1"))
struct LiveTracksAPITests {
    @Test func searchResolvesAndStreamsRealAudio() async throws {
        let client = TracksAPIClient()

        let tracks = try await client.searchTracks(matching: "daft punk", limit: 3)
        let track = try #require(tracks.first)
        let maybeURL = await client.streamURL(for: track)
        let url = try #require(maybeURL)

        var request = URLRequest(url: url)
        request.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
        request.setValue(TracksAPIClient.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode

        #expect(status == 206 || status == 200)
        // "fLaC": proves the host returned audio bytes, not an error page.
        #expect(data.prefix(4) == Data([0x66, 0x4C, 0x61, 0x43]))
        #expect(track.durationSeconds ?? 0 > 0)
    }
}
