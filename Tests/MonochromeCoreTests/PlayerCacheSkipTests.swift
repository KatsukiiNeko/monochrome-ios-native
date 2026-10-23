// PlayerCacheSkipTests.swift: the 10-second window for cancelling a background download.
import Foundation
import Testing
@testable import MonochromeCore

private final class TestClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_000)
}

@MainActor
private final class QuietEngine: PlaybackEngine {
    var onEvent: ((PlaybackEvent) -> Void)?
    private(set) var loadedURLs: [URL] = []

    func load(url: URL, contentType: String?) async throws {
        loadedURLs.append(url)
    }

    func play() {}
    func pause() {}
    func seek(to seconds: Double) {}
    func stop() {}
}

private struct FixedResolver: TrackURLResolver {
    func url(for track: Track) async throws -> URL {
        URL(string: "https://tracks.example/track/\(track.streamID ?? "x")")!
    }

    func contentType(for track: Track) async -> String? { "audio/flac" }
}

private actor RecordingCache: AudioCaching {
    private(set) var storedIDs: [String] = []
    private(set) var cancelled: [(id: String, reason: String)] = []

    func cachedAudio(for track: Track, quality: AudioQuality?) async -> CachedAudio? { nil }

    func store(
        _ track: Track,
        quality: AudioQuality?,
        url: URL,
        contentType: String?,
        format: AudioFormat?,
        duration: Double?
    ) async {
        storedIDs.append(track.id)
    }

    func cancelDownload(for track: Track, quality: AudioQuality?, reason: String) async {
        cancelled.append((track.id, reason))
    }
}

private func streamTrack(_ id: String) -> Track {
    Track(
        id: Track.remoteIDPrefix + id,
        title: "Stream \(id)",
        provider: "monochrome",
        streamID: id,
        audioQuality: .lossless
    )
}

@MainActor
@Suite("Player cache skip policy")
struct PlayerCacheSkipTests {
    @Test func skippingWithinTenSecondsCancelsTheDownload() async {
        let clock = TestClock()
        let cache = RecordingCache()
        let controller = PlayerController(
            engine: QuietEngine(),
            resolver: FixedResolver(),
            cache: cache,
            now: { clock.now }
        )
        await controller.play(tracks: [streamTrack("1"), streamTrack("2")], startingAt: 0)
        await controller.handle(.ready(duration: 100, format: AudioFormat(codec: "flac")))
        try? await Task.sleep(for: .milliseconds(20))

        clock.now += 5
        await controller.next()
        try? await Task.sleep(for: .milliseconds(20))

        let cancelled = await cache.cancelled
        #expect(cancelled.map(\.id) == [Track.remoteIDPrefix + "1"])
        #expect(cancelled.first?.reason == "skipped")
    }

    @Test func skippingAfterTenSecondsLetsTheDownloadFinish() async {
        let clock = TestClock()
        let cache = RecordingCache()
        let controller = PlayerController(
            engine: QuietEngine(),
            resolver: FixedResolver(),
            cache: cache,
            now: { clock.now }
        )
        await controller.play(tracks: [streamTrack("1"), streamTrack("2")], startingAt: 0)
        await controller.handle(.ready(duration: 100, format: AudioFormat(codec: "flac")))
        try? await Task.sleep(for: .milliseconds(20))

        clock.now += 11
        await controller.next()
        try? await Task.sleep(for: .milliseconds(20))

        #expect(await cache.cancelled.isEmpty)
        #expect(await cache.storedIDs == [Track.remoteIDPrefix + "1"])
    }

    @Test func twoSequentialStreamsBothStartAStore() async {
        let cache = RecordingCache()
        let controller = PlayerController(
            engine: QuietEngine(),
            resolver: FixedResolver(),
            cache: cache
        )
        await controller.play(tracks: [streamTrack("1"), streamTrack("2")], startingAt: 0)
        await controller.handle(.ready(duration: 100, format: AudioFormat(codec: "flac")))
        try? await Task.sleep(for: .milliseconds(20))
        await controller.next()
        await controller.handle(.ready(duration: 90, format: AudioFormat(codec: "flac")))
        try? await Task.sleep(for: .milliseconds(20))

        let stored = await cache.storedIDs
        #expect(stored == [Track.remoteIDPrefix + "1", Track.remoteIDPrefix + "2"])
    }
}
