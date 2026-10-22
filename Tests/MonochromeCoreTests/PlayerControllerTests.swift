// PlayerControllerTests.swift: host tests for playback transitions using a fake engine.
import Foundation
import Testing
@testable import MonochromeCore

@MainActor
private final class FakeEngine: PlaybackEngine {
    var onEvent: ((PlaybackEvent) -> Void)?
    private(set) var loadedURLs: [URL] = []
    private(set) var playCount = 0
    private(set) var pauseCount = 0
    private(set) var seeks: [Double] = []
    private(set) var stopCount = 0
    var loadError: (any Error)?

    func load(url: URL) async throws {
        loadedURLs.append(url)
        if let loadError { throw loadError }
    }

    func play() { playCount += 1 }
    func pause() { pauseCount += 1 }
    func seek(to seconds: Double) { seeks.append(seconds) }
    func stop() { stopCount += 1 }
}

private struct LoadFailure: LocalizedError {
    var errorDescription: String? { "cannot decode audio" }
}

private func track(_ id: String, duration: Double? = nil) -> Track {
    Track(id: id, title: "Track \(id)", durationSeconds: duration, fileName: "\(id).m4a")
}

@MainActor
@Suite("PlayerController")
struct PlayerControllerTests {
    private func makeController() -> (PlayerController, FakeEngine) {
        let engine = FakeEngine()
        let controller = PlayerController(engine: engine) { track in
            URL(fileURLWithPath: "/library/\(track.fileName)")
        }
        return (controller, engine)
    }

    @Test func playLoadsAndStartsSelectedTrack() async {
        let (controller, engine) = makeController()

        await controller.play(tracks: [track("a"), track("b")], startingAt: 1)

        #expect(controller.state == .playing)
        #expect(controller.currentTrack?.id == "b")
        #expect(engine.loadedURLs.map(\.lastPathComponent) == ["b.m4a"])
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
        let controller = PlayerController(engine: engine) { _ in nil }

        await controller.play(tracks: [track("a")], startingAt: 0)

        if case .failed = controller.state {} else {
            Issue.record("expected failed state, got \(controller.state)")
        }
        #expect(engine.loadedURLs.isEmpty)
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
        #expect(controller.state == .idle)
        #expect(engine.stopCount == 1)
    }

    @Test func previousRestartsTrackAfterThreeSeconds() async {
        let (controller, engine) = makeController()
        await controller.play(tracks: [track("a"), track("b")], startingAt: 1)
        await controller.handle(.position(12))

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
        let (controller, _) = makeController()
        await controller.play(tracks: [track("a"), track("b")], startingAt: 0)

        await controller.handle(.finished)

        #expect(controller.currentTrack?.id == "b")
        #expect(controller.state == .playing)
    }

    @Test func finishedAtEndGoesIdle() async {
        let (controller, _) = makeController()
        await controller.play(tracks: [track("a")], startingAt: 0)

        await controller.handle(.finished)

        #expect(controller.state == .idle)
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
        let (controller, _) = makeController()
        await controller.play(tracks: [track("a")], startingAt: 0)
        #expect(controller.duration == 0)

        await controller.handle(.ready(duration: 42))

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
        let (controller, _) = makeController()
        await controller.play(tracks: [track("a", duration: 50)], startingAt: 0)

        await controller.handle(.position(17.5))
        #expect(controller.position == 17.5)

        await controller.handle(.failed("stream ended"))
        #expect(controller.state == .failed("stream ended"))
    }
}
