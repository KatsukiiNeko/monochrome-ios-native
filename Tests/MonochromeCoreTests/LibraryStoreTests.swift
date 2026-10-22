import Foundation
import Testing
@testable import MonochromeCore

@Suite("LibraryStore")
struct LibraryStoreTests {
    private func temporaryStore() -> (LibraryStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = dir.appendingPathComponent("library.json")
        return (LibraryStore(fileURL: url), dir)
    }

    @Test func missingFileLoadsAsEmptyLibrary() throws {
        let (store, _) = temporaryStore()
        #expect(try store.load().isEmpty)
    }

    @Test func saveThenLoadRoundTrips() throws {
        let (store, dir) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let tracks = [Track(id: "1", title: "A", fileName: "1.flac"), Track(id: "2", title: "B", fileName: "2.flac")]

        try store.save(tracks)

        #expect(try store.load() == tracks)
    }

    @Test func decodesFixtureWithMissingOptionalFields() throws {
        let url = try #require(Bundle.module.url(forResource: "library", withExtension: "json", subdirectory: "Fixtures"))
        let tracks = try LibraryStore(fileURL: url).load()

        #expect(tracks.count == 2)
        #expect(tracks[0].title == "One More Time")
        #expect(tracks[0].durationSeconds == 320)
        #expect(tracks[1].artist == "")
        #expect(tracks[1].album == "")
        #expect(tracks[1].durationSeconds == nil)
        #expect(tracks[1].title == "Untagged Demo")
    }

    @Test func rejectsCorruptJSON() throws {
        let (store, dir) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.fileURL)

        #expect(throws: (any Error).self) { try store.load() }
    }
}
