// EngineEventTokenTests.swift: stale engine events and overlapping loads.
import Foundation
import Testing
@testable import MonochromeCore

@MainActor
private final class TokenEngine: PlaybackEngine {
    var onEvent: ((PlaybackEngineEvent) -> Void)?
    private(set) var lastToken: PlaybackToken?

    func load(url: URL, contentType: String?, headers: [String: String], token: PlaybackToken) async throws {
        lastToken = token
    }

    func play() {}
    func pause() {}
    func seek(to seconds: Double) {}
    func stop() {}

    func emit(_ event: PlaybackEvent, token: PlaybackToken? = nil) {
        guard let token = token ?? lastToken else { return }
        onEvent?(PlaybackEngineEvent(token: token, event: event))
    }
}

private struct FixedResolver: TrackURLResolver {
    func playbackSource(for track: Track) async throws -> PlaybackSource {
        .localFile(
            url: URL(fileURLWithPath: "/library/\(track.id).m4a"),
            providerID: track.provider,
            quality: track.audioQuality
        )
    }
}

private func track(_ id: String) -> Track {
    Track(id: id, title: "Track \(id)", fileName: "\(id).m4a")
}

/// The rule the engine applies before it touches the player: only the newest
/// accepted load may commit its item.
private func commit(
    _ token: PlaybackToken,
    arbiter: inout PlaybackLoadArbiter,
    active: inout String
) throws {
    guard arbiter.owns(token) else { throw PlaybackSuperseded() }
    active = "older"
}

@MainActor
@Suite("Engine event tokens")
struct EngineEventTokenTests {
    private func makePlayer() async -> (PlayerController, TokenEngine) {
        let engine = TokenEngine()
        let player = PlayerController(engine: engine, resolver: FixedResolver())
        await player.play(tracks: [track("a"), track("b")], startingAt: 0)
        return (player, engine)
    }

    @Test func stalePositionIsIgnored() async {
        let (player, engine) = await makePlayer()
        engine.emit(.position(17))
        #expect(player.position == 17)

        engine.emit(.position(99), token: PlaybackToken(value: 0))
        #expect(player.position == 17)
    }

    @Test func staleFailureDoesNotChangeState() async {
        let (player, engine) = await makePlayer()
        engine.emit(.failed("old stream"), token: PlaybackToken(value: 0))
        await player.waitForPendingEvents()
        #expect(player.state == .playing)
        #expect(player.currentTrack?.id == "a")
    }

    @Test func staleFinishDoesNotAdvance() async {
        let (player, engine) = await makePlayer()
        engine.emit(.finished, token: PlaybackToken(value: 0))
        await player.waitForPendingEvents()
        #expect(player.currentTrack?.id == "a")
        #expect(player.state == .playing)
    }

    @Test func staleReadyDoesNotChangeDuration() async {
        let (player, engine) = await makePlayer()
        engine.emit(.ready(duration: 99, format: nil), token: PlaybackToken(value: 0))
        #expect(player.duration == 0)
    }

    @Test func currentEventsStillApply() async {
        let (player, engine) = await makePlayer()
        engine.emit(.ready(duration: 42, format: nil))
        engine.emit(.position(5))
        #expect(player.duration == 42)
        #expect(player.position == 5)
    }

    @Test func overlappingLoadsKeepTheNewestItem() async {
        var arbiter = PlaybackLoadArbiter()
        let older = PlaybackToken(value: 1)
        let newer = PlaybackToken(value: 2)
        let acceptedOlder = arbiter.accept(older)
        var active = "none"
        // The newer load starts and commits while the older one is suspended.
        let acceptedNewer = arbiter.accept(newer)
        #expect(acceptedOlder)
        #expect(acceptedNewer)
        try? commit(newer, arbiter: &arbiter, active: &active)
        #expect(active == "older")

        // The older load resumes last; its commit must be refused.
        active = "newer"
        do {
            try commit(older, arbiter: &arbiter, active: &active)
            Issue.record("an older load replaced the newer item")
        } catch is PlaybackSuperseded {
            // expected
        } catch {
            Issue.record("unexpected error: \(error)")
        }
        #expect(active == "newer")
    }

    @Test func stopKillsAnInFlightLoad() async {
        var arbiter = PlaybackLoadArbiter()
        let token = PlaybackToken(value: 3)
        let accepted = arbiter.accept(token)
        #expect(accepted)
        arbiter.invalidateAll()
        var active = "newer"
        do {
            try commit(token, arbiter: &arbiter, active: &active)
            Issue.record("a load survived a stop")
        } catch is PlaybackSuperseded {
            // expected
        } catch {
            Issue.record("unexpected error: \(error)")
        }
        #expect(active == "newer")
    }
}
