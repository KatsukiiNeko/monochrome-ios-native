// PlaybackOwnershipRaceTests.swift: a late resolver must not replace a newer attempt.
import Foundation
import Testing
@testable import MonochromeCore

/// A gate a test opens when it decides an await may finish.
private actor Gate {
    private var open = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    private var didStart = false

    func wait() async {
        if !didStart {
            didStart = true
            startedWaiters.forEach { $0.resume() }
            startedWaiters.removeAll()
        }
        if open { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func waitUntilStarted() async {
        if didStart { return }
        await withCheckedContinuation { startedWaiters.append($0) }
    }

    func release() {
        open = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

/// Holds the resolution of named tracks until the test releases them.
private actor GatedResolver: TrackURLResolver {
    private let gates: [String: Gate]

    init(gates: [String: Gate]) {
        self.gates = gates
    }

    func playbackSource(for track: Track) async throws -> PlaybackSource {
        await gates[track.id]?.wait()
        let url = URL(fileURLWithPath: "/library/\(track.id).m4a")
        return .localFile(url: url, providerID: track.provider, quality: track.audioQuality)
    }
}

@MainActor
private final class RecordingEngine: PlaybackEngine {
    var onEvent: ((PlaybackEngineEvent) -> Void)?
    private(set) var loadedURLs: [URL] = []

    func load(url: URL, contentType: String?, headers: [String: String], token: PlaybackToken) async throws {
        loadedURLs.append(url)
    }

    func play() {}
    func pause() {}
    func seek(to seconds: Double) {}
    func stop() {}

    var activeFile: String? { loadedURLs.last?.deletingPathExtension().lastPathComponent }
}

private func track(_ id: String) -> Track {
    Track(id: id, title: "Track \(id)", fileName: "\(id).m4a")
}

@MainActor
@Suite("Playback ownership races")
struct PlaybackOwnershipRaceTests {
    @Test func onlyTheLatestRequestedTrackBecomesActive() async {
        let gateA = Gate()
        let resolver = GatedResolver(gates: ["a": gateA])
        let engine = RecordingEngine()
        let player = PlayerController(engine: engine, resolver: resolver)

        let first = Task { await player.play(tracks: [track("a"), track("b")], startingAt: 0) }
        await gateA.waitUntilStarted()

        await player.next()
        #expect(player.currentTrack?.id == "b")
        #expect(engine.activeFile == "b")

        await gateA.release()
        await first.value

        #expect(player.currentTrack?.id == "b")
        #expect(player.state == .playing)
        #expect(engine.loadedURLs.map { $0.deletingPathExtension().lastPathComponent } == ["b"])
    }

    @Test func fiveRapidSkipsResolveOutOfOrderAndOnlyTheLastWins() async {
        let gates = ["a": Gate(), "b": Gate(), "c": Gate(), "d": Gate()]
        let resolver = GatedResolver(gates: gates)
        let engine = RecordingEngine()
        let player = PlayerController(engine: engine, resolver: resolver)
        let ids = ["a", "b", "c", "d", "e"]

        let first = Task { await player.play(tracks: ids.map(track), startingAt: 0) }
        await gates["a"]!.waitUntilStarted()

        var skips: [Task<Void, Never>] = []
        for index in 1..<4 {
            skips.append(Task { await player.next() })
            await gates[ids[index]]!.waitUntilStarted()
        }
        // The last track has no gate, so this skip completes immediately.
        await player.next()
        #expect(player.currentTrack?.id == "e")

        // Release the slow resolvers newest first, then oldest last.
        await gates["d"]!.release()
        await gates["c"]!.release()
        await gates["b"]!.release()
        await gates["a"]!.release()
        await first.value
        for skip in skips { await skip.value }

        #expect(player.currentTrack?.id == "e")
        #expect(player.state == .playing)
        #expect(engine.loadedURLs.map { $0.deletingPathExtension().lastPathComponent } == ["e"])
    }
}
