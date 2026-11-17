// PlaylistTests.swift: collection rules, store durability and schema migration.
import Foundation
import Testing
@testable import MonochromeCore

private func track(_ id: String, provider: String = Track.remoteIDPrefix, title: String = "") -> Track {
    Track(
        id: provider == Track.localProvider ? id : Track.remoteIDPrefix + id,
        title: title.isEmpty ? "Song \(id)" : title,
        artist: "Artist \(id)",
        album: "Album \(id)",
        durationSeconds: 180,
        provider: provider
    )
}

@Suite("PlaylistCollection")
struct PlaylistCollectionTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private var collection: PlaylistCollection { PlaylistCollection() }

    @Test("create, rename and delete follow the caps")
    mutating func crud() {
        var c = collection
        let first = c.create(named: "  Road trip  ", now: now)
        #expect(first != nil)
        #expect(first?.name == "Road trip")
        #expect(c.create(named: "   ", now: now) == nil)

        while c.playlists.count < PlaylistCollection.maxPlaylists {
            _ = c.create(named: "Filler", now: now)
        }
        #expect(c.playlists.count == PlaylistCollection.maxPlaylists)
        #expect(c.create(named: "Over cap", now: now) == nil)

        let renamed = c.rename(id: first!.id, to: "", now: now)
        #expect(renamed == false)
        let renamedAgain = c.rename(id: first!.id, to: "Trip", now: now)
        #expect(renamedAgain)
        #expect(c.playlist(id: first!.id)?.name == "Trip")

        let deleted = c.delete(id: first!.id)
        #expect(deleted)
        #expect(c.playlist(id: first!.id) == nil)
        let deletedAgain = c.delete(id: first!.id)
        #expect(deletedAgain == false)
    }

    @Test("duplicate copies items and gets a fresh id")
    mutating func duplicate() {
        var c = collection
        let source = c.create(named: "Mix", now: now)
        #expect(source != nil)
        #expect(c.add(track("a"), to: source!.id, now: now) == .added)
        #expect(c.add(track("b"), to: source!.id, now: now) == .added)

        let copy = c.duplicate(id: source!.id, now: now)
        #expect(copy != nil)
        #expect(copy?.id != source?.id)
        #expect(copy?.name == "Mix Copy")
        #expect(copy?.items == c.playlist(id: source!.id)?.items)

        let removed = c.remove(at: 0, from: copy!.id, now: now)
        #expect(removed != nil)
        #expect(c.playlist(id: source!.id)?.items.count == 2)
    }

    @Test("add rejects duplicates unless allowed")
    mutating func duplicateHandling() {
        var c = collection
        let playlist = c.create(named: "Mix", now: now)
        #expect(playlist != nil)
        let song = track("a")
        #expect(c.add(song, to: playlist!.id, now: now) == .added)
        #expect(c.add(song, to: playlist!.id, now: now) == .duplicate)
        #expect(c.playlist(id: playlist!.id)?.items.count == 1)
        #expect(c.add(song, to: playlist!.id, allowDuplicate: true, now: now) == .added)
        #expect(c.playlist(id: playlist!.id)?.items.count == 2)

        #expect(c.add(song, to: "missing", now: now) == .playlistNotFound)
        #expect(c.add([track("b"), song, track("c")], to: playlist!.id, now: now) == 2)
    }

    @Test("the track cap holds")
    mutating func trackCap() {
        var c = collection
        let playlist = c.create(named: "Big", now: now)
        #expect(playlist != nil)
        var overCap: PlaylistAddResult?
        for index in 0..<PlaylistCollection.maxTracksPerPlaylist {
            overCap = c.add(track("id\(index)"), to: playlist!.id, now: now)
        }
        #expect(overCap == .added)
        let extra = c.add(track("extra"), to: playlist!.id, now: now)
        #expect(extra == .playlistFull)
        #expect(c.playlist(id: playlist!.id)?.items.count == PlaylistCollection.maxTracksPerPlaylist)
    }

    @Test("reorder follows Array.move semantics and remove keeps order")
    mutating func reorderAndRemove() {
        var c = collection
        let playlist = c.create(named: "Order", now: now)
        #expect(playlist != nil)
        for id in ["a", "b", "c"] {
            _ = c.add(track(id), to: playlist!.id, now: now)
        }
        c.moveTrack(in: playlist!.id, from: 0, to: 2, now: now)
        #expect(c.playlist(id: playlist!.id)?.items.map(\.id) == [
            Track.remoteIDPrefix + "b",
            Track.remoteIDPrefix + "a",
            Track.remoteIDPrefix + "c",
        ])
        c.moveTrack(in: playlist!.id, from: 0, to: 3, now: now)
        #expect(c.playlist(id: playlist!.id)?.items.map(\.id) == [
            Track.remoteIDPrefix + "a",
            Track.remoteIDPrefix + "c",
            Track.remoteIDPrefix + "b",
        ])

        #expect(c.remove(at: 5, from: playlist!.id, now: now) == nil)
        #expect(c.remove(at: 0, from: playlist!.id, now: now)?.id == Track.remoteIDPrefix + "a")
        #expect(c.playlist(id: playlist!.id)?.items.count == 2)
    }

    @Test("mutating a playlist bumps its updatedAt only")
    mutating func updatedAt() {
        var c = collection
        let later = now.addingTimeInterval(60)
        let playlist = c.create(named: "Times", now: now)
        #expect(playlist != nil)
        #expect(c.playlist(id: playlist!.id)?.updatedAt == now)
        _ = c.add(track("a"), to: playlist!.id, now: later)
        #expect(c.playlist(id: playlist!.id)?.createdAt == now)
        #expect(c.playlist(id: playlist!.id)?.updatedAt == later)
    }
}

@Suite("PlaylistStore")
struct PlaylistStoreTests {
    private var directory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("playlists-\(UUID().uuidString)", isDirectory: true)
    }

    private func store(at url: URL) -> PlaylistStore {
        PlaylistStore(fileURL: url, now: { Date(timeIntervalSince1970: 42) })
    }

    @Test("round trip keeps playlists and track snapshots")
    func roundTrip() throws {
        let url = directory.appendingPathComponent("playlists.json")
        var collection = PlaylistCollection()
        let playlist = collection.create(named: "Trip", now: Date(timeIntervalSince1970: 1))
        #expect(playlist != nil)
        let added = collection.add(track("a"), to: playlist!.id, now: Date(timeIntervalSince1970: 2))
        #expect(added == .added)
        try store(at: url).save(collection)

        let loaded = store(at: url).load()
        #expect(loaded == collection)
        #expect(loaded.schemaVersion == PlaylistCollection.schemaVersion)
        #expect(loaded.playlist(id: playlist!.id)?.items.first?.artist == "Artist a")
    }

    @Test("a file without a schema version migrates in place")
    func legacyMigration() throws {
        let url = directory.appendingPathComponent("playlists.json")
        let legacy = """
        {"playlists":[{"id":"p1","name":"Old","createdAt":1700000000,"updatedAt":1700000000,"items":[]}]}
        """
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try legacy.data(using: .utf8)!.write(to: url)

        let loaded = store(at: url).load()
        #expect(loaded.schemaVersion == PlaylistCollection.schemaVersion)
        #expect(loaded.playlists.count == 1)
        #expect(loaded.playlists[0].name == "Old")
    }

    @Test("a corrupt file is quarantined and the store starts empty")
    func corruptionRecovery() throws {
        let url = directory.appendingPathComponent("playlists.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{not json".data(using: .utf8)!.write(to: url)

        #expect(store(at: url).load().playlists.isEmpty)
        let quarantined = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        #expect(quarantined.contains { $0.hasPrefix("playlists.corrupt-") })
        #expect(!FileManager.default.fileExists(atPath: url.path))

        var collection = PlaylistCollection()
        _ = collection.create(named: "Fresh", now: Date(timeIntervalSince1970: 3))
        try store(at: url).save(collection)
        #expect(store(at: url).load().playlists.count == 1)
    }

    @Test("an oversized file is quarantined instead of decoded")
    func oversizedQuarantine() throws {
        let url = directory.appendingPathComponent("playlists.json")
        let directoryURL = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data(count: PlaylistStore.maxBytes + 10).write(to: url)

        #expect(store(at: url).load().playlists.isEmpty)
        let quarantined = try FileManager.default.contentsOfDirectory(atPath: directoryURL.path)
        #expect(quarantined.contains { $0.hasPrefix("playlists.corrupt-") })
    }
}
