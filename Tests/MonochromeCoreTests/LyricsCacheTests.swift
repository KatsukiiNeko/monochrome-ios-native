// LyricsCacheTests.swift: TTLs, negative caching, provider isolation and the size bound.
import Foundation
import Testing
@testable import MonochromeCore

@Suite("LyricsCache")
struct LyricsCacheTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("lyrics-cache-\(UUID().uuidString)", isDirectory: true)
    }

    private func query(_ id: String = "track-1") -> LyricsQuery {
        LyricsQuery(trackID: id, title: "Synthetic Song", artist: "Synthetic Artist", duration: 200)
    }

    private func synced(_ text: String = "Synthetic line") -> LyricsResult {
        LyricsResult(content: .synced([LyricLine(time: 1, text: text)]), source: "Fake")
    }

    private func days(_ value: Double) -> TimeInterval { value * 24 * 60 * 60 }

    @Test func positiveEntriesLiveForThirtyDays() async {
        let directory = temporaryDirectory()
        let cache = LyricsCache(directory: directory)
        let query = query()
        await cache.store(synced(), for: query, provider: "Fake", now: t0)

        #expect(await cache.result(for: query, provider: "Fake", now: t0.addingTimeInterval(days(29))) != nil)
        #expect(await cache.result(for: query, provider: "Fake", now: t0.addingTimeInterval(days(31))) == nil)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func notFoundEntriesLiveForSevenDays() async {
        let directory = temporaryDirectory()
        let cache = LyricsCache(directory: directory)
        let query = query()
        let missing = LyricsResult(content: .notFound, source: "Fake")
        await cache.store(missing, for: query, provider: "Fake", now: t0)

        let atSix = await cache.result(for: query, provider: "Fake", now: t0.addingTimeInterval(days(6)))
        #expect(atSix?.isNotFound == true)
        #expect(await cache.result(for: query, provider: "Fake", now: t0.addingTimeInterval(days(8))) == nil)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func expiredEntriesCanStillAnswerOffline() async {
        let directory = temporaryDirectory()
        let cache = LyricsCache(directory: directory)
        let query = query()
        await cache.store(synced(), for: query, provider: "Fake", now: t0)

        let stale = await cache.result(
            for: query,
            provider: "Fake",
            now: t0.addingTimeInterval(days(90)),
            allowExpired: true
        )
        #expect(stale != nil)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func entriesAreIsolatedByProviderAndTrack() async {
        let directory = temporaryDirectory()
        let cache = LyricsCache(directory: directory)
        await cache.store(synced("A"), for: query("1"), provider: "Fake", now: t0)
        await cache.store(synced("B"), for: query("1"), provider: "Other", now: t0)

        let fake = await cache.result(for: query("1"), provider: "Fake", now: t0)
        let other = await cache.result(for: query("1"), provider: "Other", now: t0)
        #expect(fake != other)
        #expect(await cache.result(for: query("2"), provider: "Fake", now: t0) == nil)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func theSizeBoundEvictsTheLeastRecentlyUsedEntry() async {
        let directory = temporaryDirectory()
        let cache = LyricsCache(directory: directory, maxEntries: 2)
        let a = query("a")
        let b = query("b")
        let c = query("c")

        await cache.store(synced("A"), for: a, provider: "Fake", now: t0)
        await cache.store(synced("B"), for: b, provider: "Fake", now: t0.addingTimeInterval(1))
        _ = await cache.result(for: a, provider: "Fake", now: t0.addingTimeInterval(2))
        await cache.store(synced("C"), for: c, provider: "Fake", now: t0.addingTimeInterval(3))

        #expect(await cache.count() == 2)
        #expect(await cache.result(for: a, provider: "Fake", now: t0.addingTimeInterval(4)) != nil)
        #expect(await cache.result(for: b, provider: "Fake", now: t0.addingTimeInterval(4)) == nil)
        #expect(await cache.result(for: c, provider: "Fake", now: t0.addingTimeInterval(4)) != nil)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func keysAreStableAndSafeForTheFileSystem() {
        let key = LyricsCache.key(provider: "LRCLIB", trackID: "stream:../../Track 1")
        #expect(key == LyricsCache.key(provider: "LRCLIB", trackID: "stream:../../Track 1"))
        #expect(!key.contains("/"))
        #expect(!key.contains(":"))
        #expect(key != LyricsCache.key(provider: "LRCLIB", trackID: "stream:../../Track 2"))
    }
}
