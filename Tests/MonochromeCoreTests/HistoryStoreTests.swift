// HistoryStoreTests.swift: host tests for the recently-played list.
import Foundation
import Testing
@testable import MonochromeCore

@Suite("HistoryStore")
struct HistoryStoreTests {
    private func temporaryStore(limit: Int = 3) -> (HistoryStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (HistoryStore(fileURL: dir.appendingPathComponent("history.json"), limit: limit), dir)
    }

    @Test func recordsNewestFirst() throws {
        let (store, dir) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        try store.record(Track(id: "a", title: "A", fileName: "a.m4a"))
        let tracks = try store.record(Track(id: "b", title: "B", fileName: "b.m4a"))

        #expect(tracks.map(\.id) == ["b", "a"])
        #expect(try store.load().map(\.id) == ["b", "a"])
    }

    @Test func replayMovesToFrontWithoutDuplicating() throws {
        let (store, dir) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try store.record(Track(id: "a", title: "A", fileName: "a.m4a"))
        try store.record(Track(id: "b", title: "B", fileName: "b.m4a"))

        let tracks = try store.record(Track(id: "a", title: "A", fileName: "a.m4a"))

        #expect(tracks.map(\.id) == ["a", "b"])
    }

    @Test func capsTheList() throws {
        let (store, dir) = temporaryStore(limit: 2)
        defer { try? FileManager.default.removeItem(at: dir) }

        try store.record(Track(id: "a", title: "A", fileName: "a.m4a"))
        try store.record(Track(id: "b", title: "B", fileName: "b.m4a"))
        let tracks = try store.record(Track(id: "c", title: "C", fileName: "c.m4a"))

        #expect(tracks.map(\.id) == ["c", "b"])
    }

    @Test func corruptFileStartsOver() throws {
        let (store, dir) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{oops".utf8).write(to: store.fileURL)

        let tracks = try store.record(Track(id: "a", title: "A", fileName: "a.m4a"))

        #expect(tracks.map(\.id) == ["a"])
    }
}
