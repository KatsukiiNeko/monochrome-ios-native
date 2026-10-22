// FavoritesStoreTests.swift: host tests for favorites.json persistence and its v1 migration.
import Foundation
import Testing
@testable import MonochromeCore

@Suite("FavoritesStore")
struct FavoritesStoreTests {
    private func temporaryStore() -> (FavoritesStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (FavoritesStore(fileURL: dir.appendingPathComponent("favorites.json")), dir)
    }

    @Test func missingFileLoadsEmpty() throws {
        let (store, _) = temporaryStore()
        #expect(try store.load() == .tracks([]))
    }

    @Test func saveThenLoadRoundTrips() throws {
        let (store, dir) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let tracks = [
            Track(id: "b", title: "Second", fileName: "b.m4a"),
            Track(id: "a", title: "First", provider: "monochrome", streamID: "1"),
        ]
        try store.save(tracks)

        #expect(try store.load() == .tracks(tracks))
    }

    @Test func legacyIDFileIsReportedNotDropped() throws {
        let (store, dir) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"["a","b"]"#.utf8).write(to: store.fileURL)

        #expect(try store.load() == .legacyIDs(["a", "b"]))
    }

    @Test func rejectsCorruptJSON() throws {
        let (store, dir) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{oops".utf8).write(to: store.fileURL)

        #expect(throws: (any Error).self) { try store.load() }
    }
}
