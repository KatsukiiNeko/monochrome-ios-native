// LyricsTimingStoreTests.swift: host tests for the per-track lyrics offset.
import Foundation
import Testing
@testable import MonochromeCore

private func makeStore() throws -> (LyricsTimingStore, UserDefaults, String) {
    let suite = "monochrome-lyrics-timing-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    return (LyricsTimingStore(defaults: defaults), defaults, suite)
}

@Suite("LyricsTimingStore")
struct LyricsTimingStoreTests {
    @Test func keepsTheKeyFormatOfEarlierBuilds() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.setDelay(0.25, for: "track-1")

        #expect(defaults.double(forKey: "lyrics.timingDelay.track-1") == 0.25)
    }

    @Test func readsBackTheStoredOffset() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.setDelay(-0.5, for: "track-1")

        #expect(store.delay(for: "track-1") == -0.5)
    }

    @Test func zeroRemovesTheKey() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.setDelay(0.75, for: "track-1")
        store.setDelay(0, for: "track-1")

        #expect(defaults.object(forKey: "lyrics.timingDelay.track-1") == nil)
        #expect(store.delay(for: "track-1") == 0)
    }

    @Test func clampsBeyondTheSupportedRange() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(store.setDelay(12, for: "track-1") == LyricsTimingStore.maximumDelay)
        #expect(store.setDelay(-12, for: "track-1") == -LyricsTimingStore.maximumDelay)
        #expect(store.delay(for: "track-1") == -LyricsTimingStore.maximumDelay)
    }

    @Test func noTrackUsesASeparateKeyAndReadsAsInSync() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(store.delay(for: nil) == 0)
        store.setDelay(1, for: nil)
        #expect(defaults.double(forKey: "lyrics.timingDelay.none") == 1)
        #expect(store.delay(for: "track-1") == 0)
    }
}
