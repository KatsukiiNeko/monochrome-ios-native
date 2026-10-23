// NowPlayingSnapshotTests.swift: host tests for snapshot mapping and remote command routing.
import Foundation
import Testing
@testable import MonochromeCore

@MainActor
private final class FakeRemoteTarget: RemoteCommandTarget {
    var isPlaying: Bool
    private(set) var toggleCount = 0
    private(set) var nextCount = 0
    private(set) var previousCount = 0
    private(set) var seeks: [Double] = []

    init(isPlaying: Bool = false) {
        self.isPlaying = isPlaying
    }

    func togglePlayPause() async { toggleCount += 1 }
    func next() async { nextCount += 1 }
    func previous() async { previousCount += 1 }
    func seek(to seconds: Double) { seeks.append(seconds) }
}

private func snapshotTrack() -> Track {
    Track(id: "a", title: "Song", artist: "Artist", album: "Album", durationSeconds: 200)
}

@MainActor
@Suite("NowPlayingSnapshot")
struct NowPlayingSnapshotTests {
    @Test func nilTrackIsAnEmptyStoppedSnapshot() {
        let snapshot = NowPlayingSnapshot.make(
            track: nil,
            state: .idle,
            position: 12,
            duration: 100,
            hasNext: true,
            hasPrevious: true
        )

        #expect(snapshot.title.isEmpty)
        #expect(snapshot.artist.isEmpty)
        #expect(snapshot.album.isEmpty)
        #expect(snapshot.duration == 0)
        #expect(snapshot.elapsed == 0)
        #expect(snapshot.rate == 0)
        #expect(!snapshot.canPlay)
        #expect(!snapshot.canPause)
        #expect(!snapshot.canNext)
        #expect(!snapshot.canPrevious)
        #expect(!snapshot.canSeek)
        #expect(snapshot.playbackState == .stopped)
    }

    @Test func playingSnapshotEnablesPauseAndSeek() {
        let snapshot = NowPlayingSnapshot.make(
            track: snapshotTrack(),
            state: .playing,
            position: 30,
            duration: 120,
            hasNext: true,
            hasPrevious: false
        )

        #expect(snapshot.title == "Song")
        #expect(snapshot.artist == "Artist")
        #expect(snapshot.album == "Album")
        #expect(snapshot.duration == 120)
        #expect(snapshot.elapsed == 30)
        #expect(snapshot.rate == 1.0)
        #expect(!snapshot.canPlay)
        #expect(snapshot.canPause)
        #expect(snapshot.canNext)
        #expect(!snapshot.canPrevious)
        #expect(snapshot.canSeek)
        #expect(snapshot.playbackState == .playing)
    }

    @Test func playingWithoutDurationCannotSeek() {
        let snapshot = NowPlayingSnapshot.make(
            track: snapshotTrack(),
            state: .playing,
            position: 0,
            duration: 0,
            hasNext: false,
            hasPrevious: false
        )

        #expect(!snapshot.canSeek)
        #expect(snapshot.rate == 1.0)
    }

    @Test func pausedSnapshotEnablesPlay() {
        let snapshot = NowPlayingSnapshot.make(
            track: snapshotTrack(),
            state: .paused,
            position: 5,
            duration: 120,
            hasNext: false,
            hasPrevious: true
        )

        #expect(snapshot.rate == 0)
        #expect(snapshot.canPlay)
        #expect(!snapshot.canPause)
        #expect(snapshot.canSeek)
        #expect(snapshot.canPrevious)
        #expect(!snapshot.canNext)
        #expect(snapshot.playbackState == .paused)
    }

    @Test func loadingSnapshotDisablesTransportUntilReady() {
        let snapshot = NowPlayingSnapshot.make(
            track: snapshotTrack(),
            state: .loading,
            position: 0,
            duration: 120,
            hasNext: true,
            hasPrevious: true
        )

        #expect(snapshot.rate == 0)
        #expect(!snapshot.canPlay)
        #expect(!snapshot.canPause)
        #expect(!snapshot.canSeek)
        #expect(snapshot.canNext)
        #expect(snapshot.canPrevious)
        #expect(snapshot.playbackState == .paused)
    }

    @Test func failedSnapshotAllowsRetry() {
        let snapshot = NowPlayingSnapshot.make(
            track: snapshotTrack(),
            state: .failed("boom"),
            position: 0,
            duration: 0,
            hasNext: false,
            hasPrevious: false
        )

        #expect(snapshot.rate == 0)
        #expect(snapshot.canPlay)
        #expect(!snapshot.canPause)
        #expect(!snapshot.canSeek)
        #expect(snapshot.playbackState == .stopped)
    }

    @Test func idleSnapshotIsStoppedAndCanStart() {
        let snapshot = NowPlayingSnapshot.make(
            track: snapshotTrack(),
            state: .idle,
            position: 0,
            duration: 120,
            hasNext: false,
            hasPrevious: false
        )

        #expect(snapshot.canPlay)
        #expect(!snapshot.canPause)
        #expect(snapshot.playbackState == .stopped)
    }

    @Test func playIsIgnoredWhileAlreadyPlaying() async {
        let target = FakeRemoteTarget(isPlaying: true)

        await perform(.play, on: target)

        #expect(target.toggleCount == 0)
    }

    @Test func playTogglesWhenNotPlaying() async {
        let target = FakeRemoteTarget(isPlaying: false)

        await perform(.play, on: target)

        #expect(target.toggleCount == 1)
    }

    @Test func pauseIsIgnoredWhileAlreadyPaused() async {
        let target = FakeRemoteTarget(isPlaying: false)

        await perform(.pause, on: target)

        #expect(target.toggleCount == 0)
    }

    @Test func pauseTogglesWhenPlaying() async {
        let target = FakeRemoteTarget(isPlaying: true)

        await perform(.pause, on: target)

        #expect(target.toggleCount == 1)
    }

    @Test func toggleAlwaysToggles() async {
        let playing = FakeRemoteTarget(isPlaying: true)
        let paused = FakeRemoteTarget(isPlaying: false)

        await perform(.toggle, on: playing)
        await perform(.toggle, on: paused)

        #expect(playing.toggleCount == 1)
        #expect(paused.toggleCount == 1)
    }

    @Test func nextAndPreviousAreForwarded() async {
        let target = FakeRemoteTarget()

        await perform(.next, on: target)
        await perform(.previous, on: target)

        #expect(target.nextCount == 1)
        #expect(target.previousCount == 1)
    }

    @Test func seekForwardsThePosition() async {
        let target = FakeRemoteTarget()

        await perform(.seek(42.5), on: target)

        #expect(target.seeks == [42.5])
    }
}
