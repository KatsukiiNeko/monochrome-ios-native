import Foundation
import Testing
@testable import MonochromeCore

@Suite("FavoritesStore")
struct FavoritesStoreTests {
    private func temporaryStore() -> (FavoritesStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (FavoritesStore(fileURL: dir.appendingPathComponent("favorites.json")), dir)
    }

    @Test func missingFileLoadsEmptySet() throws {
        let (store, _) = temporaryStore()
        #expect(try store.load().isEmpty)
    }

    @Test func saveThenLoadRoundTrips() throws {
        let (store, dir) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        try store.save(["b", "a"])

        #expect(try store.load() == ["a", "b"])
    }

    @Test func rejectsCorruptJSON() throws {
        let (store, dir) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{oops".utf8).write(to: store.fileURL)

        #expect(throws: (any Error).self) { try store.load() }
    }
}
