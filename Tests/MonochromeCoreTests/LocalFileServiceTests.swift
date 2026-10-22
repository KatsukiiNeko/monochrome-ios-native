import Foundation
import Testing
@testable import MonochromeCore

private struct StubMetadataReader: TrackMetadataReading {
    var value: TrackMetadata?
    func metadata(for url: URL) async -> TrackMetadata? { value }
}

@Suite("LocalFileService")
struct LocalFileServiceTests {
    private struct Fixture {
        let service: LocalFileService
        let root: URL
    }

    private func makeService(metadata: TrackMetadata?) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let media = root.appendingPathComponent("Media")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let service = LocalFileService(
            mediaDirectory: media,
            store: LibraryStore(fileURL: root.appendingPathComponent("library.json")),
            metadataReader: StubMetadataReader(value: metadata)
        )
        return Fixture(service: service, root: root)
    }

    private func makeSourceFile(in root: URL, name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data("fake audio".utf8).write(to: url)
        return url
    }

    @Test func importCopiesFileAndUsesTags() async throws {
        let fixture = try makeService(metadata: TrackMetadata(title: "Tagged", artist: "Artist", album: "Album", durationSeconds: 12))
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let source = try makeSourceFile(in: fixture.root, name: "song.flac")

        let track = try await fixture.service.importTrack(from: source, fallbackTitle: "ignored")

        #expect(track.title == "Tagged")
        #expect(track.artist == "Artist")
        #expect(track.durationSeconds == 12)
        #expect(track.fileName == "\(track.id).flac")
        let copied = fixture.service.mediaDirectory.appendingPathComponent(track.fileName)
        #expect(FileManager.default.fileExists(atPath: copied.path))
        #expect(try await fixture.service.allTracks() == [track])
    }

    @Test func importFallsBackToFileNameWhenTagsAreMissing() async throws {
        let fixture = try makeService(metadata: nil)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let source = try makeSourceFile(in: fixture.root, name: "My Song.mp3")

        let track = try await fixture.service.importTrack(from: source, fallbackTitle: nil)

        #expect(track.title == "My Song")
        #expect(track.artist == "")
        #expect(track.fileName.hasSuffix(".mp3"))
    }

    @Test func deleteRemovesTrackAndFile() async throws {
        let fixture = try makeService(metadata: TrackMetadata(title: "Gone"))
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let source = try makeSourceFile(in: fixture.root, name: "song.m4a")
        let track = try await fixture.service.importTrack(from: source, fallbackTitle: nil)
        let copied = fixture.service.mediaDirectory.appendingPathComponent(track.fileName)

        try await fixture.service.delete(track)

        #expect(try await fixture.service.allTracks().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: copied.path))
    }

    @Test func tracksAreListedNewestFirst() async throws {
        let fixture = try makeService(metadata: nil)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let first = try await fixture.service.importTrack(
            from: makeSourceFile(in: fixture.root, name: "one.mp3"),
            fallbackTitle: "One"
        )
        let second = try await fixture.service.importTrack(
            from: makeSourceFile(in: fixture.root, name: "two.mp3"),
            fallbackTitle: "Two"
        )

        let tracks = try await fixture.service.allTracks()

        #expect(tracks.map(\.id) == [second.id, first.id])
    }

    @Test func importWritesArtworkAndDeleteRemovesIt() async throws {
        let artwork = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let fixture = try makeService(metadata: TrackMetadata(title: "With art", artworkData: artwork))
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let source = try makeSourceFile(in: fixture.root, name: "song.flac")

        let track = try await fixture.service.importTrack(from: source, fallbackTitle: nil)
        let artworkName = try #require(track.artworkFileName)
        let artworkURL = fixture.service.mediaDirectory.appendingPathComponent(artworkName)
        #expect(try Data(contentsOf: artworkURL) == artwork)

        try await fixture.service.delete(track)

        #expect(!FileManager.default.fileExists(atPath: artworkURL.path))
    }

    @Test func importWithoutArtworkLeavesFieldEmpty() async throws {
        let fixture = try makeService(metadata: TrackMetadata(title: "No art"))
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let track = try await fixture.service.importTrack(
            from: makeSourceFile(in: fixture.root, name: "song.flac"),
            fallbackTitle: nil
        )

        #expect(track.artworkFileName == nil)
    }
}
