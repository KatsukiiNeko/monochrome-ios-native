// PlayerCacheSkipTests.swift: the half-heard threshold for staging a stream.
import Foundation
import Testing
@testable import MonochromeCore

@MainActor
private final class QuietEngine: PlaybackEngine {
    var onEvent: ((PlaybackEngineEvent) -> Void)?
    private(set) var loadedURLs: [URL] = []
    private(set) var lastToken: PlaybackToken?

    func load(url: URL, contentType: String?, headers: [String: String], token: PlaybackToken) async throws {
        lastToken = token
        loadedURLs.append(url)
    }

    func emit(_ event: PlaybackEvent) {
        guard let lastToken else { return }
        onEvent?(PlaybackEngineEvent(token: lastToken, event: event))
    }

    func play() {}
    func pause() {}
    func seek(to seconds: Double) {}
    func stop() {}
}

private struct FixedResolver: TrackURLResolver {
    func playbackSource(for track: Track) async throws -> PlaybackSource {
        .remoteStream(url: URL(string: "https://tracks.example/track/\(track.streamID ?? "x")")!, headers: [:], providerID: track.provider, quality: track.audioQuality, contentType: nil)
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
@Suite("Player cache promotion policy")
struct PlayerCacheSkipTests {
    @Test func skippingBeforeHalfNeverStartsTheStore() async {
        let cache = RecordingCache()
        let engine = QuietEngine()
        let controller = PlayerController(
            engine: engine,
            resolver: FixedResolver(),
            cache: cache
        )
        await controller.play(tracks: [streamTrack("1"), streamTrack("2")], startingAt: 0)
        engine.emit(.ready(duration: 100, format: AudioFormat(codec: "flac")))
        for second in 1...30 {
            engine.emit(.position(Double(second)))
        }
        try? await Task.sleep(for: .milliseconds(20))

        await controller.next()
        try? await Task.sleep(for: .milliseconds(20))

        #expect(await cache.storedIDs.isEmpty)
        #expect(await cache.cancelled.isEmpty)
    }

    @Test func skippingAfterHalfLetsTheStoreFinish() async {
        let cache = RecordingCache()
        let engine = QuietEngine()
        let controller = PlayerController(
            engine: engine,
            resolver: FixedResolver(),
            cache: cache
        )
        await controller.play(tracks: [streamTrack("1"), streamTrack("2")], startingAt: 0)
        engine.emit(.ready(duration: 100, format: AudioFormat(codec: "flac")))
        for second in 1...60 {
            engine.emit(.position(Double(second)))
        }
        try? await Task.sleep(for: .milliseconds(20))
        #expect(await cache.storedIDs == [Track.remoteIDPrefix + "1"])

        await controller.next()
        try? await Task.sleep(for: .milliseconds(20))

        #expect(await cache.storedIDs == [Track.remoteIDPrefix + "1"])
        #expect(await cache.cancelled.isEmpty)
    }

    @Test func aSeekToTheEndDoesNotCountAsListening() async {
        let cache = RecordingCache()
        let engine = QuietEngine()
        let controller = PlayerController(
            engine: engine,
            resolver: FixedResolver(),
            cache: cache
        )
        await controller.play(tracks: [streamTrack("1")], startingAt: 0)
        engine.emit(.ready(duration: 100, format: AudioFormat(codec: "flac")))
        for second in 1...5 {
            engine.emit(.position(Double(second)))
        }
        engine.emit(.position(95))
        try? await Task.sleep(for: .milliseconds(20))

        #expect(await cache.storedIDs.isEmpty)
    }

    @Test func twoSequentialStreamsBothStartAStoreAfterHalf() async {
        let cache = RecordingCache()
        let engine = QuietEngine()
        let controller = PlayerController(
            engine: engine,
            resolver: FixedResolver(),
            cache: cache
        )
        await controller.play(tracks: [streamTrack("1"), streamTrack("2")], startingAt: 0)
        engine.emit(.ready(duration: 100, format: AudioFormat(codec: "flac")))
        for second in 1...60 {
            engine.emit(.position(Double(second)))
        }
        await controller.next()
        engine.emit(.ready(duration: 90, format: AudioFormat(codec: "flac")))
        for second in 1...60 {
            engine.emit(.position(Double(second)))
        }
        try? await Task.sleep(for: .milliseconds(20))

        let stored = await cache.storedIDs
        #expect(stored == [Track.remoteIDPrefix + "1", Track.remoteIDPrefix + "2"])
    }
}
