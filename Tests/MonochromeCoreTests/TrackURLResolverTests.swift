// TrackURLResolverTests.swift: host tests for local and streaming URL resolution.
import Foundation
import Testing
@testable import MonochromeCore

private func makeDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("monochrome-resolver-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite("TrackURLResolver")
struct TrackURLResolverTests {
    @Test func resolvesAnExistingLocalFile() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("song.m4a")
        try Data("audio".utf8).write(to: file)

        let resolver = DefaultTrackResolver(localDirectory: directory)
        let url = try await resolver.url(for: Track(title: "Song", fileName: "song.m4a"))

        #expect(url == file)
    }

    @Test func missingLocalFileThrows() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let resolver = DefaultTrackResolver(localDirectory: directory)

        await #expect(throws: TrackResolutionError.self) {
            _ = try await resolver.url(for: Track(title: "Gone", fileName: "gone.m4a"))
        }
    }

    @Test func streamTrackUsesTheCatalogClient() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = TracksAPIClient(baseURL: URL(string: "https://catalog.test")!)
        let resolver = DefaultTrackResolver(localDirectory: directory, client: client)

        let url = try await resolver.url(
            for: Track(id: "stream:7", title: "Song", provider: "monochrome", streamID: "7")
        )

        #expect(url.absoluteString == "https://catalog.test/track/7")
    }

    @Test func streamTrackWithoutClientIsNotStreamable() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let resolver = DefaultTrackResolver(localDirectory: directory)

        await #expect(throws: TrackResolutionError.notStreamable("Song")) {
            _ = try await resolver.url(
                for: Track(id: "stream:7", title: "Song", provider: "monochrome", streamID: "7")
            )
        }
    }

    @Test func streamTrackWithoutIDIsNotStreamable() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = TracksAPIClient(baseURL: URL(string: "https://catalog.test")!)
        let resolver = DefaultTrackResolver(localDirectory: directory, client: client)

        await #expect(throws: TrackResolutionError.self) {
            _ = try await resolver.url(for: Track(title: "Song", provider: "monochrome"))
        }
    }
}
