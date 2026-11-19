// PlayerControllerTests.swift: host tests for playback transitions using a fake engine.
import Foundation
import Testing
@testable import MonochromeCore

@MainActor
private final class FakeEngine: PlaybackEngine {
    var onEvent: ((PlaybackEngineEvent) -> Void)?
    private(set) var loadedURLs: [URL] = []
    private(set) var lastToken: PlaybackToken?
    private(set) var tokens: [PlaybackToken] = []
    private(set) var contentTypes: [String?] = []
    private(set) var playCount = 0
    private(set) var pauseCount = 0
    private(set) var seeks: [Double] = []
    private(set) var stopCount = 0
    var loadError: (any Error)?

    func load(url: URL, contentType: String?, headers: [String: String], token: PlaybackToken) async throws {
        lastToken = token
        tokens.append(token)
        loadedURLs.append(url)
        contentTypes.append(contentType)
        if let loadError { throw loadError }
    }

    /// Emits an event with the token of the most recent load.
    func emit(_ event: PlaybackEvent) {
        guard let lastToken else { return }
        emit(event, token: lastToken)
    }

    func emit(_ event: PlaybackEvent, token: PlaybackToken) {
        onEvent?(PlaybackEngineEvent(token: token, event: event))
    }

    func play() { playCount += 1 }
    func pause() { pauseCount += 1 }
    func seek(to seconds: Double) { seeks.append(seconds) }
    func stop() { stopCount += 1 }
}

private struct LoadFailure: LocalizedError {
    var errorDescription: String? { "cannot decode audio" }
}

/// Fails the first `failures` resolutions so retry behaviour is observable.
private actor FakeResolver: TrackURLResolver {
    private var failuresRemaining: Int
    private var requestedIDs: [String] = []

    init(failures: Int = 0) {
        self.failuresRemaining = failures
    }

    func playbackSource(for track: Track) async throws -> PlaybackSource {
        requestedIDs.append(track.id)
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw LoadFailure()
        }
        let name = track.fileName.isEmpty ? track.id : track.fileName
        let url = URL(fileURLWithPath: "/library/\(name)")
        return track.isStreaming
            ? .remoteStream(url: url, headers: [:], providerID: track.provider, quality: track.audioQuality, contentType: nil)
            : .localFile(url: url, providerID: track.provider, quality: track.audioQuality)
    }

    func requests() -> [String] { requestedIDs }
}

/// Serves a canned hit and records what the controller asks to cache.
private actor FakeCache: AudioCaching {
    private var hit: CachedAudio?
    private(set) var storedIDs: [String] = []
    private(set) var storedURLs: [URL] = []
    private(set) var lookups = 0

    func setHit(_ audio: CachedAudio?) { hit = audio }

    func cachedAudio(for track: Track, quality: AudioQuality?) async -> CachedAudio? {
        lookups += 1
        return hit
    }

    func store(
        _ track: Track,
        quality: AudioQuality?,
        url: URL,
        contentType: String?,
        format: AudioFormat?,
        duration: Double?
    ) async {
        storedIDs.append(track.id)
        storedURLs.append(url)
    }
}

/// Resolves to a remote stream, so the preflight path is exercised.
private struct StreamResolver: TrackURLResolver {
    func playbackSource(for track: Track) async throws -> PlaybackSource {
        .remoteStream(
            url: URL(string: "https://tracks.test/track/\(track.streamID ?? track.id)")!,
            headers: [:],
            providerID: track.provider,
            quality: track.audioQuality,
            contentType: "audio/flac"
        )
    }
}

private actor FakePreflight: StreamPreflighting {
    private let result: PreflightResult
    private(set) var urls: [URL] = []

    init(result: PreflightResult = PreflightResult(isReady: true, requestCount: 1, elapsedMs: 12, lastStatus: 206)) {
        self.result = result
    }

    func waitUntilReady(url: URL, isCancelled: @Sendable () -> Bool) async -> PreflightResult {
        if !isCancelled() { urls.append(url) }
        return result
    }

    func requestCount() -> Int { urls.count }
}

private actor FakeDownloads: DownloadedAudioProviding {
    private var file: DownloadedAudio?

    func setFile(_ audio: DownloadedAudio?) { file = audio }

    func downloadedFile(for track: Track) async -> DownloadedAudio? { file }
}

private func track(_ id: String, duration: Double? = nil) -> Track {
    Track(id: id, title: "Track \(id)", durationSeconds: duration, fileName: "\(id).m4a")
}

private func streamTrack(_ id: String) -> Track {
    Track(id: Track.remoteIDPrefix + id, title: "Stream \(id)", provider: "monochrome", streamID: id)
}

@MainActor
@Suite("PlayerController")
struct PlayerControllerTests {
    private func makeController(resolver: FakeResolver = FakeResolver()) -> (PlayerController, FakeEngine) {
        let engine = FakeEngine()
        let controller = PlayerController(engine: engine, resolver: resolver)
        return (controller, engine)
    }

    @Test func downloadIsPreferredOverCacheAndNetwork() async {
        let engine = FakeEngine()
        let resolver = FakeResolver()
        let cache = FakeCache()
        await cache.setHit(CachedAudio(url: URL(fileURLWithPath: "/cache/a.flac")))
        let downloads = FakeDownloads()
        await downloads.setFile(DownloadedAudio(
            url: URL(fileURLWithPath: "/downloads/a.flac"),
            format: AudioFormat(codec: "flac"),
            duration: 123,
            byteSize: 99
        ))
        let controller = PlayerController(
            engine: engine,
            resolver: resolver,
            cache: cache,
            downloads: downloads
        )

        await controller.play(tracks: [streamTrack("a")], startingAt: 0)

        #expect(engine.loadedURLs.map(\.lastPathComponent) == ["a.flac"])
        #expect(engine.loadedURLs.first?.deletingLastPathComponent().lastPathComponent == "downloads")
        #expect(controller.isCurrentFromDownload)
        #expect(!controller.isCurrentFromCache)
        #expect(controller.duration == 123)
        #expect(await resolver.requests().isEmpty)
        #expect(await cache.lookups == 0)
    }

    @Test func cacheIsPreferredOverNetworkWhenNoDownloadExists() async {
        let engine = FakeEngine()
        let resolver = FakeResolver()
        let cache = FakeCache()
        await cache.setHit(CachedAudio(url: URL(fileURLWithPath: "/cache/a.flac")))
        let downloads = FakeDownloads()
        let controller = PlayerController(
            engine: engine,
            resolver: resolver,
            cache: cache,
            downloads: downloads
        )

        await controller.play(tracks: [streamTrack("a")], startingAt: 0)

        #expect(engine.loadedURLs.map(\.lastPathComponent) == ["a.flac"])
        #expect(engine.loadedURLs.first?.deletingLastPathComponent().lastPathComponent == "cache")
        #expect(controller.isCurrentFromCache)
        #expect(!controller.isCurrentFromDownload)
        #expect(await resolver.requests().isEmpty)
        #expect(await cache.lookups == 1)
    }

    @Test func networkIsUsedWhenNeitherStoreHasTheTrack() async {
        let engine = FakeEngine()
        let resolver = FakeResolver()
        let cache = FakeCache()
        let downloads = FakeDownloads()
        let controller = PlayerController(
            engine: engine,
            resolver: resolver,
            cache: cache,
            downloads: downloads
        )

        await controller.play(tracks: [streamTrack("a")], startingAt: 0)

        #expect(engine.loadedURLs.map(\.lastPathComponent) == ["stream:a"])
        #expect(!controller.isCurrentFromCache)
        #expect(!controller.isCurrentFromDownload)
        #expect(await resolver.requests().count == 1)
        #expect(await cache.lookups == 1)
    }

    @Test func networkAttemptLogsEveryPhase() async {
        let controller = PlayerController(
            engine: FakeEngine(),
            resolver: FakeResolver(),
            cache: FakeCache(),
            downloads: FakeDownloads()
        )
        var lines: [String] = []
        controller.log = { lines.append($0) }

        await controller.play(tracks: [streamTrack("a")], startingAt: 0)

        let attempt = lines.last(where: { $0.hasPrefix("attempt=") })
        #expect(attempt?.contains("lookup=") == true)
        #expect(attempt?.contains("resolve=") == true)
        #expect(attempt?.contains("asset=") == true)
        #expect(attempt?.contains("ready=") == true)
        #expect(attempt?.contains("via=network") == true)
        #expect(attempt?.contains("stream:a") == false)
    }

    @Test func failedAttemptLogsOneErrorShape() async {
        let (controller, engine) = makeController()
        engine.loadError = LoadFailure()
        var lines: [String] = []
        controller.log = { lines.append($0) }

        await controller.play(tracks: [streamTrack("a")], startingAt: 0)

        let attempts = lines.filter { $0.hasPrefix("attempt=") }
        #expect(attempts.count == 2)
        #expect(attempts.last?.contains("failed=") == true)
        #expect(attempts.last?.contains("error=") == true)
        #expect(controller.state == .failed("cannot decode audio"))
    }

    @Test func networkPlayPreflightsTheStreamOnce() async {
        let engine = FakeEngine()
        let preflight = FakePreflight()
        let controller = PlayerController(
            engine: engine,
            resolver: StreamResolver(),
            cache: FakeCache(),
            downloads: FakeDownloads(),
            preflight: preflight
        )

        await controller.play(tracks: [streamTrack("a")], startingAt: 0)

        #expect(controller.state == .playing)
        #expect(await preflight.requestCount() == 1)
        #expect(engine.loadedURLs.count == 1)
    }

    @Test func aCacheHitSkipsThePreflight() async {
        let engine = FakeEngine()
        let cache = FakeCache()
        await cache.setHit(CachedAudio(url: URL(fileURLWithPath: "/cache/a.flac")))
        let preflight = FakePreflight()
        let controller = PlayerController(
            engine: engine,
            resolver: FakeResolver(),
            cache: cache,
            downloads: FakeDownloads(),
            preflight: preflight
        )

        await controller.play(tracks: [streamTrack("a")], startingAt: 0)

        #expect(controller.state == .playing)
        #expect(await preflight.requestCount() == 0)
    }

    @Test func aPodcastSkipsThePreflight() async {
        let engine = FakeEngine()
        let preflight = FakePreflight()
        var podcast = streamTrack("episode-1")
        podcast.provider = MusicSourceID.podcast.rawValue
        let controller = PlayerController(
            engine: engine,
            resolver: StreamResolver(),
            cache: FakeCache(),
            downloads: FakeDownloads(),
            preflight: preflight
        )

        await controller.play(tracks: [podcast], startingAt: 0)

        #expect(controller.state == .playing)
        #expect(await preflight.requestCount() == 0)
        #expect(engine.loadedURLs.count == 1)
    }

    @Test func aColdStreamFailsOnceThenRetriesFresh() async {
        let engine = FakeEngine()
        let preflight = FakePreflight(
            result: PreflightResult(isReady: false, requestCount: 5, elapsedMs: 7_900, lastStatus: 503)
        )
        let controller = PlayerController(
            engine: engine,
            resolver: StreamResolver(),
            cache: FakeCache(),
            downloads: FakeDownloads(),
            preflight: preflight
        )

        await controller.play(tracks: [streamTrack("a")], startingAt: 0)

        // One fresh attempt after the first failure, and the engine never saw the URL.
        #expect(await preflight.requestCount() == 2)
        #expect(engine.loadedURLs.isEmpty)
        #expect(controller.state == .failed("The stream did not answer. Check the connection, then retry."))
    }

    @Test func playLoadsAndStartsSelectedTrack() async {
        let (controller, engine) = makeController()

        await controller.play(tracks: [track("a"), track("b")], startingAt: 1)

        #expect(controller.state == .playing)
        #expect(controller.currentTrack?.id == "b")
        #expect(engine.loadedURLs.map(\.lastPathComponent) == ["b.m4a"])
        #expect(engine.contentTypes == [nil])
        #expect(engine.playCount == 1)
    }

    @Test func loadFailureSurfacesMessageAndDoesNotPlay() async {
        let (controller, engine) = makeController()
        engine.loadError = LoadFailure()

        await controller.play(tracks: [track("a")], startingAt: 0)

        #expect(controller.state == .failed("cannot decode audio"))
        #expect(engine.playCount == 0)
    }

    @Test func missingURLFailsWithoutTouchingEngine() async {
        let engine = FakeEngine()
        let resolver = FakeResolver(failures: 5)
        let controller = PlayerController(engine: engine, resolver: resolver)

        await controller.play(tracks: [track("a")], startingAt: 0)

        if case .failed = controller.state {} else {
            Issue.record("expected failed state, got \(controller.state)")
        }
        #expect(engine.loadedURLs.isEmpty)
        // A local file is not retried: the failure cannot heal by resolving again.
        let requests = await resolver.requests()
        #expect(requests.count == 1)
    }

    @Test func togglePausesAndResumesWithoutReloading() async {
        let (controller, engine) = makeController()
        await controller.play(tracks: [track("a")], startingAt: 0)

        await controller.togglePlayPause()
        #expect(controller.state == .paused)
        #expect(engine.pauseCount == 1)

        await controller.togglePlayPause()
        #expect(controller.state == .playing)
        #expect(engine.playCount == 2)
        #expect(engine.loadedURLs.count == 1)
    }

    @Test func toggleFromIdleStartsQueuedTrack() async {
        let (controller, engine) = makeController()
        controller.append([track("a")])

        await controller.togglePlayPause()

        #expect(controller.state == .playing)
        #expect(engine.loadedURLs.count == 1)
    }

    @Test func nextAdvancesThenStopsAtEnd() async {
        let (controller, engine) = makeController()
        await controller.play(tracks: [track("a"), track("b")], startingAt: 0)

        await controller.next()
        #expect(controller.currentTrack?.id == "b")
        #expect(controller.state == .playing)

        await controller.next()
        #expect(controller.state == .stopped(.endOfQueue))
        #expect(engine.stopCount == 1)
    }

    @Test func previousRestartsTrackAfterThreeSeconds() async {
        let (controller, engine) = makeController()
        await controller.play(tracks: [track("a"), track("b")], startingAt: 1)
        engine.emit(.position(12))

        await controller.previous()

        #expect(controller.currentTrack?.id == "b")
        #expect(engine.seeks == [0])
        #expect(controller.position == 0)
    }

    @Test func previousGoesBackNearStart() async {
        let (controller, engine) = makeController()
        await controller.play(tracks: [track("a"), track("b")], startingAt: 1)

        await controller.previous()

        #expect(controller.currentTrack?.id == "a")
        #expect(engine.loadedURLs.count == 2)
    }

    @Test func finishedAdvancesToNextTrack() async {
        let (controller, engine) = makeController()
        await controller.play(tracks: [track("a"), track("b")], startingAt: 0)

        engine.emit(.finished)
        await controller.waitForPendingEvents()

        #expect(controller.currentTrack?.id == "b")
        #expect(controller.state == .playing)
    }

    @Test func finishedAtEndStopsWithEndOfQueue() async {
        let (controller, engine) = makeController()
        await controller.play(tracks: [track("a")], startingAt: 0)

        engine.emit(.finished)
        await controller.waitForPendingEvents()

        #expect(controller.state == .stopped(.endOfQueue))
        #expect(controller.position == 0)
    }

    @Test func seekClampsToDuration() async {
        let (controller, engine) = makeController()
        await controller.play(tracks: [track("a", duration: 100)], startingAt: 0)

        controller.seek(to: 250)
        #expect(controller.position == 100)
        #expect(engine.seeks == [100])

        controller.seek(to: -5)
        #expect(controller.position == 0)
    }

    @Test func engineDurationFillsInMissingTag() async {
        let (controller, engine) = makeController()
        await controller.play(tracks: [track("a")], startingAt: 0)
        #expect(controller.duration == 0)

        engine.emit(.ready(duration: 42, format: nil))

        #expect(controller.duration == 42)
    }

    @Test func removingCurrentTrackLoadsFollowingTrack() async {
        let (controller, _) = makeController()
        await controller.play(tracks: [track("a"), track("b"), track("c")], startingAt: 1)

        await controller.removeTrack(at: 1)

        #expect(controller.currentTrack?.id == "c")
        #expect(controller.queue.tracks.map(\.id) == ["a", "c"])
    }

    @Test func removingOtherTrackKeepsCurrent() async {
        let (controller, engine) = makeController()
        await controller.play(tracks: [track("a"), track("b"), track("c")], startingAt: 2)

        await controller.removeTrack(at: 0)

        #expect(controller.currentTrack?.id == "c")
        #expect(engine.loadedURLs.count == 1)
    }

    @Test func jumpLoadsTrackAtindex() async {
        let (controller, engine) = makeController()
        await controller.play(tracks: [track("a"), track("b")], startingAt: 0)

        await controller.jump(to: 1)

        #expect(controller.currentTrack?.id == "b")
        #expect(engine.loadedURLs.last?.lastPathComponent == "b.m4a")
    }

    @Test func positionAndFailureEventsUpdateState() async {
        let (controller, engine) = makeController()
        await controller.play(tracks: [track("a", duration: 50)], startingAt: 0)

        engine.emit(.position(17.5))
        #expect(controller.position == 17.5)

        engine.emit(.failed("stream ended"))
        await controller.waitForPendingEvents()
        #expect(controller.state == .failed("stream ended"))
    }

    // MARK: - Streaming retries

    @Test func streamIsResolvedAgainOnceAfterAFailure() async {
        let engine = FakeEngine()
        let resolver = FakeResolver(failures: 1)
        let controller = PlayerController(engine: engine, resolver: resolver)

        await controller.play(tracks: [streamTrack("42")], startingAt: 0)

        #expect(controller.state == .playing)
        #expect(engine.loadedURLs.count == 1)
        let requests = await resolver.requests()
        #expect(requests.count == 2)
    }

    @Test func streamGivesUpAfterOneRetry() async {
        let engine = FakeEngine()
        let resolver = FakeResolver(failures: 5)
        let controller = PlayerController(engine: engine, resolver: resolver)

        await controller.play(tracks: [streamTrack("42")], startingAt: 0)

        if case .failed = controller.state {} else {
            Issue.record("expected failed state, got \(controller.state)")
        }
        #expect(engine.loadedURLs.isEmpty)
        let requests = await resolver.requests()
        #expect(requests.count == 2)
    }

    @Test func expiredStreamReloadsOnce() async {
        let (controller, engine) = makeController()
        await controller.play(tracks: [streamTrack("42")], startingAt: 0)

        engine.emit(.failed("HTTP 403"))
        await controller.waitForPendingEvents()

        #expect(controller.state == .playing)
        #expect(engine.loadedURLs.count == 2)
    }

    @Test func retryAfterFailureResolvesAgain() async {
        let engine = FakeEngine()
        let resolver = FakeResolver(failures: 2)
        let controller = PlayerController(engine: engine, resolver: resolver)
        await controller.play(tracks: [streamTrack("42")], startingAt: 0)
        if case .failed = controller.state {} else {
            Issue.record("expected failed state, got \(controller.state)")
        }

        await controller.retry()

        #expect(controller.state == .playing)
        #expect(engine.loadedURLs.count == 1)
    }

    @Test func trackStartCallbackFiresPerTrack() async {
        let (controller, _) = makeController()
        var started: [String] = []
        controller.onTrackStarted = { started.append($0.id) }

        await controller.play(tracks: [track("a"), track("b")], startingAt: 0)
        await controller.next()

        #expect(started == ["a", "b"])
    }

    // MARK: - Listening events

    @Test func finishedTrackReportsACompletedPlayEvent() async {
        let (controller, engine) = makeController()
        var events: [PlayEvent] = []
        controller.onPlayEvent = { events.append($0) }

        await controller.play(tracks: [track("a", duration: 100)], startingAt: 0)
        engine.emit(.finished)
        await controller.waitForPendingEvents()

        #expect(events.count == 1)
        #expect(events.first?.outcome == .completed)
        #expect(events.first?.trackID == "a")
        #expect(events.first?.duration == 100)
    }

    @Test func leavingATrackEarlyReportsASkippedPlayEvent() async {
        let (controller, engine) = makeController()
        var events: [PlayEvent] = []
        controller.onPlayEvent = { events.append($0) }

        await controller.play(tracks: [track("a", duration: 100), track("b", duration: 100)], startingAt: 0)
        engine.emit(.position(12))
        await controller.next()

        #expect(events.count == 1)
        #expect(events.first?.outcome == .skipped)
        #expect(events.first?.listenedSeconds == 12)
    }

    @Test func advancingAfterTheEndDoesNotReportASkip() async {
        let (controller, engine) = makeController()
        var events: [PlayEvent] = []
        controller.onPlayEvent = { events.append($0) }

        await controller.play(tracks: [track("a", duration: 100), track("b", duration: 100)], startingAt: 0)
        engine.emit(.finished)
        await controller.waitForPendingEvents()

        #expect(events.count == 1)
        #expect(events.first?.outcome == .completed)
    }

    @Test func repeatOneReportsALoopedPlayEvent() async {
        let (controller, engine) = makeController()
        var events: [PlayEvent] = []
        controller.onPlayEvent = { events.append($0) }

        await controller.play(tracks: [track("a", duration: 100)], startingAt: 0)
        controller.setRepeatMode(.one)
        engine.emit(.finished)
        await controller.waitForPendingEvents()

        #expect(events.count == 1)
        #expect(events.first?.outcome == .completed)
        #expect(events.first?.loop == true)
    }

    // MARK: - Repeat modes

    @Test func repeatOneRestartsALocalTrackWithoutReloading() async {
        let (controller, engine) = makeController()
        await controller.play(tracks: [track("a")], startingAt: 0)
        controller.setRepeatMode(.one)

        engine.emit(.finished)
        await controller.waitForPendingEvents()

        #expect(controller.state == .playing)
        #expect(controller.position == 0)
        #expect(engine.seeks == [0])
        #expect(engine.loadedURLs.count == 1)
    }

    @Test func repeatOneResolvesAStreamAgain() async {
        let engine = FakeEngine()
        let resolver = FakeResolver()
        let controller = PlayerController(engine: engine, resolver: resolver)
        await controller.play(tracks: [streamTrack("42")], startingAt: 0)
        controller.setRepeatMode(.one)

        engine.emit(.finished)
        await controller.waitForPendingEvents()

        #expect(controller.state == .playing)
        #expect(engine.loadedURLs.count == 2)
        let requests = await resolver.requests()
        #expect(requests.count == 2)
    }

    @Test func repeatAllWrapsToTheFirstTrack() async {
        let (controller, engine) = makeController()
        await controller.play(tracks: [track("a"), track("b")], startingAt: 1)
        controller.setRepeatMode(.all)

        engine.emit(.finished)
        await controller.waitForPendingEvents()

        #expect(controller.currentTrack?.id == "a")
        #expect(engine.loadedURLs.last?.lastPathComponent == "a.m4a")
    }

    @Test func repeatOffStillAdvances() async {
        let (controller, engine) = makeController()
        await controller.play(tracks: [track("a"), track("b")], startingAt: 0)

        engine.emit(.finished)
        await controller.waitForPendingEvents()

        #expect(controller.currentTrack?.id == "b")
    }

    @Test func cycleRepeatModeRunsOffAllOne() {
        let (controller, _) = makeController()
        #expect(controller.repeatMode == .off)
        controller.cycleRepeatMode()
        #expect(controller.repeatMode == .all)
        controller.cycleRepeatMode()
        #expect(controller.repeatMode == .one)
        controller.cycleRepeatMode()
        #expect(controller.repeatMode == .off)
    }

    // MARK: - Audio cache

    @Test func cacheHitPlaysTheLocalFileWithoutResolving() async {
        let engine = FakeEngine()
        let resolver = FakeResolver()
        let cache = FakeCache()
        let local = URL(fileURLWithPath: "/cache/42.flac")
        await cache.setHit(
            CachedAudio(
                url: local,
                format: AudioFormat(codec: "flac", bitDepth: 16, sampleRateHz: 44_100),
                duration: 210,
                byteSize: 1_024
            )
        )
        let controller = PlayerController(engine: engine, resolver: resolver, cache: cache)

        await controller.play(tracks: [streamTrack("42")], startingAt: 0)

        #expect(controller.state == .playing)
        #expect(controller.isCurrentFromCache)
        #expect(engine.loadedURLs == [local])
        #expect(engine.contentTypes.count == 1)
        #expect(engine.contentTypes[0] == nil)
        #expect(await resolver.requests().isEmpty)
        #expect(controller.format == AudioFormat(codec: "flac", bitDepth: 16, sampleRateHz: 44_100))
        #expect(controller.duration == 210)
    }

    @Test func missStartsABackgroundStoreAfterTheItemIsReady() async {
        let engine = FakeEngine()
        let resolver = FakeResolver()
        let cache = FakeCache()
        let controller = PlayerController(engine: engine, resolver: resolver, cache: cache)

        await controller.play(tracks: [streamTrack("42")], startingAt: 0)
        engine.emit(.ready(duration: 100, format: AudioFormat(codec: "flac")))
        try? await Task.sleep(for: .milliseconds(20))

        #expect(await cache.storedIDs == [Track.remoteIDPrefix + "42"])
        #expect(controller.isCurrentFromCache == false)
    }

    @Test func repeatOneReplaysTheCachedFileInPlace() async {
        let engine = FakeEngine()
        let resolver = FakeResolver()
        let cache = FakeCache()
        let local = URL(fileURLWithPath: "/cache/42.flac")
        await cache.setHit(CachedAudio(url: local, duration: 200, byteSize: 1_024))
        let controller = PlayerController(engine: engine, resolver: resolver, cache: cache)
        await controller.play(tracks: [streamTrack("42")], startingAt: 0)
        controller.setRepeatMode(.one)

        var lines: [String] = []
        controller.log = { lines.append($0) }

        engine.emit(.finished)
        await controller.waitForPendingEvents()

        #expect(controller.state == .playing)
        #expect(engine.seeks == [0])
        #expect(engine.loadedURLs.count == 1)
        #expect(await resolver.requests().isEmpty)
        #expect(lines.contains("loop source=cache"))
    }

    @Test func switchingTracksClearsTheCacheSourceFlag() async {
        let engine = FakeEngine()
        let resolver = FakeResolver()
        let cache = FakeCache()
        await cache.setHit(CachedAudio(url: URL(fileURLWithPath: "/cache/1.flac"), byteSize: 10))
        let controller = PlayerController(engine: engine, resolver: resolver, cache: cache)
        await controller.play(tracks: [streamTrack("1"), streamTrack("2")], startingAt: 0)
        #expect(controller.isCurrentFromCache)

        await cache.setHit(nil)
        await controller.next()

        #expect(controller.currentTrack?.id == Track.remoteIDPrefix + "2")
        #expect(controller.isCurrentFromCache == false)
    }

    @Test func measuredFormatWinsOverTheCachedCopy() async {
        let engine = FakeEngine()
        let resolver = FakeResolver()
        let cache = FakeCache()
        await cache.setHit(
            CachedAudio(
                url: URL(fileURLWithPath: "/cache/42.flac"),
                format: AudioFormat(codec: "flac", bitDepth: 16, sampleRateHz: 44_100),
                duration: 210,
                byteSize: 1_024
            )
        )
        let controller = PlayerController(engine: engine, resolver: resolver, cache: cache)
        await controller.play(tracks: [streamTrack("42")], startingAt: 0)

        var lines: [String] = []
        controller.log = { lines.append($0) }
        engine.emit(
            .ready(
                duration: 210,
                format: AudioFormat(codec: "flac", sampleRateHz: 48_000, channels: 2, bitrateKbps: 1_411)
            )
        )

        #expect(controller.format?.bitDepth == 16)
        #expect(controller.format?.sampleRateHz == 48_000)
        #expect(controller.format?.channels == 2)
        #expect(controller.format?.bitrateKbps == 1_411)
        #expect(lines.contains("audiospec mismatch field=sampleRate"))
    }

    @Test func sleepTimerPausesPlaybackWhenItExpires() async {
        let (controller, engine) = makeController()
        await controller.play(tracks: [track("a")], startingAt: 0)

        controller.startSleepTimer(seconds: 0.02)
        #expect(controller.sleepTimerEnd != nil)
        try? await Task.sleep(for: .milliseconds(250))

        #expect(controller.state == .paused)
        #expect(engine.pauseCount == 1)
        #expect(controller.sleepTimerEnd == nil)
    }

    @Test func replacingTheSleepTimerLeavesOnlyTheNewDeadlineArmed() async {
        let (controller, engine) = makeController()
        await controller.play(tracks: [track("a")], startingAt: 0)

        controller.startSleepTimer(seconds: 0.02)
        controller.startSleepTimer(seconds: 60)
        try? await Task.sleep(for: .milliseconds(250))

        #expect(engine.pauseCount == 0)
        #expect(controller.sleepTimerEnd != nil)

        controller.cancelSleepTimer()
        #expect(controller.sleepTimerEnd == nil)
    }
}

@MainActor
@Suite("Queue commands")
struct QueueCommandTests {
    private func makeController() -> (PlayerController, FakeEngine) {
        let engine = FakeEngine()
        let controller = PlayerController(engine: engine, resolver: FakeResolver())
        return (controller, engine)
    }

    private var tracks: [Track] {
        ["a", "b", "c", "d"].map { Track(id: $0, title: "Track \($0)", fileName: "\($0).m4a") }
    }

    @Test("play next inserts right after the current track")
    func playNext() async {
        let (player, _) = makeController()
        await player.play(tracks: tracks, startingAt: 0)
        player.playNext(track("x"))
        player.playNext(track("y"))
        #expect(player.queue.tracks.map(\.id) == ["a", "y", "x", "b", "c", "d"])
        #expect(player.queue.current?.id == "a")
    }

    @Test("shuffle pins the current track and restores the order when toggled off")
    func shuffleAndRestore() async {
        let (player, _) = makeController()
        await player.play(tracks: tracks, startingAt: 1)
        #expect(player.queue.current?.id == "b")

        player.toggleShuffle(generator: seededGenerator(seed: 11))
        #expect(player.isShuffled)
        #expect(player.queue.current?.id == "b")
        #expect(player.queue.currentIndex == 1)
        let shuffledOrder = player.queue.tracks.map(\.id)
        #expect(Set(shuffledOrder) == Set(["a", "b", "c", "d"]))

        player.toggleShuffle(generator: seededGenerator(seed: 99))
        #expect(!player.isShuffled)
        #expect(player.queue.tracks.map(\.id) == ["a", "b", "c", "d"])
        #expect(player.queue.current?.id == "b")
        #expect(player.queue.currentIndex == 1)
    }

    @Test("single track and empty queues are no-ops")
    func shuffleEdges() async {
        let (player, _) = makeController()
        await player.play(tracks: [tracks[0]], startingAt: 0)
        player.toggleShuffle(generator: { _ in 0 })
        #expect(player.queue.tracks.map(\.id) == ["a"])

        await player.play(tracks: [], startingAt: 0)
        player.toggleShuffle(generator: { _ in 0 })
        #expect(player.queue.isEmpty)
    }

    @Test("clearing the queue stops playback and resets state")
    func clearQueue() async {
        let (player, engine) = makeController()
        await player.play(tracks: tracks, startingAt: 0)
        #expect(player.state == .playing)

        player.clearQueue()
        #expect(player.queue.isEmpty)
        #expect(player.state == .stopped(.queueCleared))
        #expect(player.currentTrack == nil)
        #expect(player.position == 0)
        #expect(!player.isShuffled)
        #expect(engine.stopCount == 1)
    }

    @Test("playing a new queue resets the shuffle state")
    func replaceResetsShuffle() async {
        let (player, _) = makeController()
        await player.play(tracks: tracks, startingAt: 0)
        player.toggleShuffle(generator: seededGenerator(seed: 5))
        #expect(player.isShuffled)

        await player.play(tracks: tracks, startingAt: 0)
        #expect(!player.isShuffled)
    }
}
