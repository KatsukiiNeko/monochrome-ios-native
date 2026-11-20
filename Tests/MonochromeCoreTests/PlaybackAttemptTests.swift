// PlaybackAttemptTests.swift: halting the old item, attempt-scoped seeks and stalls.
import Foundation
import Testing
@testable import MonochromeCore

@MainActor
private final class AttemptEngine: PlaybackEngine {
    var onEvent: ((PlaybackEngineEvent) -> Void)?
    private(set) var lastToken: PlaybackToken?
    private(set) var loadCount = 0
    private(set) var seeks: [Double] = []
    private(set) var haltCount = 0
    private(set) var stopCount = 0
    private(set) var playCount = 0
    var facts = EngineFacts.optimistic

    func load(url: URL, contentType: String?, headers: [String: String], token: PlaybackToken) async throws {
        lastToken = token
        loadCount += 1
    }

    func emit(_ event: PlaybackEvent) {
        guard let lastToken else { return }
        onEvent?(PlaybackEngineEvent(token: lastToken, event: event))
    }

    func play() { playCount += 1 }
    func pause() {}
    func seek(to seconds: Double) { seeks.append(seconds) }
    func stop() { stopCount += 1 }
    func halt() { haltCount += 1 }
}

/// Holds the resolution of one track open until the test releases it.
private actor GatedResolver: TrackURLResolver {
    private let gatedID: String
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(gatedID: String) {
        self.gatedID = gatedID
    }

    func open() {
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters = []
    }

    func playbackSource(for track: Track) async throws -> PlaybackSource {
        if track.id == gatedID && !isOpen {
            await withCheckedContinuation { waiters.append($0) }
        }
        return .remoteStream(
            url: URL(string: "https://tracks.example/track/\(track.id)")!,
            headers: [:],
            providerID: track.provider,
            quality: track.audioQuality,
            contentType: "audio/flac"
        )
    }

    func contentType(for track: Track) async -> String? { "audio/flac" }
}

private func track(_ id: String, duration: Double = 100) -> Track {
    Track(
        id: Track.remoteIDPrefix + id,
        title: "Stream \(id)",
        durationSeconds: duration,
        provider: "monochrome",
        streamID: id,
        audioQuality: .lossless
    )
}

@MainActor
@Suite("Playback attempt ownership")
struct PlaybackAttemptTests {
    @Test func aNewAttemptSilencesTheOldItemAndKeepsItsSeek() async {
        let engine = AttemptEngine()
        let resolver = GatedResolver(gatedID: Track.remoteIDPrefix + "2")
        let controller = PlayerController(engine: engine, resolver: resolver)

        await controller.play(tracks: [track("1"), track("2", duration: 200)], startingAt: 0)
        engine.emit(.ready(duration: 100, format: AudioFormat(codec: "flac")))
        #expect(controller.state == .playing)

        let switched = Task { await controller.play(tracks: [track("1"), track("2", duration: 200)], startingAt: 1) }
        try? await Task.sleep(for: .milliseconds(30))

        #expect(engine.haltCount >= 1)
        #expect(controller.state == .loading(autoPlay: true))
        #expect(controller.position == 0)
        #expect(controller.duration == 200)

        controller.seek(to: 42)
        #expect(!engine.seeks.contains(42))

        await resolver.open()
        await switched.value
        #expect(engine.seeks == [42])
        #expect(controller.position == 42)
    }

    @Test func aStallShowsBufferingAndLeavesThePositionAlone() async {
        let engine = AttemptEngine()
        let controller = PlayerController(engine: engine, resolver: GatedResolver(gatedID: ""))
        await controller.play(tracks: [track("1")], startingAt: 0)
        engine.emit(.ready(duration: 100, format: AudioFormat(codec: "flac")))
        engine.emit(.position(5))
        #expect(controller.position == 5)

        engine.facts = EngineFacts(itemStatus: .ready, timeControl: .waiting, likelyToKeepUp: false, bufferEmpty: true)
        await controller.reconcileNow()
        #expect(controller.isBuffering)
        #expect(controller.position == 5)

        engine.facts = .optimistic
        await controller.reconcileNow()
        #expect(!controller.isBuffering)
        #expect(controller.position == 5)
    }

    @Test func aLongStallReloadsOnceThenResumes() async {
        let engine = AttemptEngine()
        let controller = PlayerController(engine: engine, resolver: GatedResolver(gatedID: ""))
        await controller.play(tracks: [track("1")], startingAt: 0)
        engine.emit(.ready(duration: 100, format: AudioFormat(codec: "flac")))
        engine.emit(.position(30))
        let loadsBefore = engine.loadCount

        engine.facts = EngineFacts(itemStatus: .ready, timeControl: .waiting, likelyToKeepUp: false, bufferEmpty: true)
        for _ in 0..<9 {
            await controller.reconcileNow()
        }

        #expect(engine.loadCount == loadsBefore + 1)
        #expect(engine.seeks.last == 30)
    }
}
