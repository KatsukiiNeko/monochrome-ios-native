// NowPlayingPlanTests.swift: the publication rules and the player projection.
import Foundation
import Testing
@testable import MonochromeCore

private let sample = NowPlayingIdentity(
    trackID: "track-a",
    title: "A",
    artist: "Artist",
    album: "Album",
    duration: 180
)

private func showing(
    _ identity: NowPlayingIdentity?,
    playing: Bool = true,
    stop: StopReason? = nil,
    artwork: Bool = false
) -> NowPlayingState {
    NowPlayingState(identity: identity, isPlaying: playing, stopReason: stop, artworkReady: artwork)
}

private func track(
    _ id: String,
    duration: Double? = nil,
    album: String = ""
) -> Track {
    Track(id: id, title: "Title \(id)", album: album, durationSeconds: duration)
}

@Suite("Now Playing planner")
struct NowPlayingPlannerTests {
    @Test func newTrackPublishesTheWholeIdentity() {
        #expect(NowPlayingPlanner.actions(from: nil, to: showing(sample)) == [.publishIdentity])
    }

    @Test func pauseOrResumeUpdatesStateOnly() {
        let shown = showing(sample)
        #expect(NowPlayingPlanner.actions(from: shown, to: showing(sample, playing: false)) == [.updatePlaybackState])
        #expect(NowPlayingPlanner.actions(from: showing(sample, playing: false), to: shown) == [.updatePlaybackState])
    }

    @Test func durationArrivalRepublishes() {
        var withDuration = sample
        withDuration.duration = 210
        #expect(NowPlayingPlanner.actions(from: showing(sample), to: showing(withDuration)) == [.publishIdentity])
    }

    @Test func artworkArrivalAttachesIt() {
        let shown = showing(sample)
        #expect(NowPlayingPlanner.actions(from: shown, to: showing(sample, artwork: true)) == [.attachArtwork])
        // Already shown for this track: nothing to do.
        #expect(NowPlayingPlanner.actions(from: showing(sample, artwork: true), to: showing(sample, artwork: true)).isEmpty)
    }

    @Test func transientMissingTrackHoldsMetadata() {
        let shown = showing(sample, artwork: true)
        let blip = showing(nil, artwork: false)
        #expect(NowPlayingPlanner.actions(from: shown, to: blip).isEmpty)
    }

    @Test func explicitStopClearsExactlyOnce() {
        let shown = showing(sample)
        let stopped = showing(nil, playing: false, stop: .queueCleared)
        #expect(NowPlayingPlanner.actions(from: shown, to: stopped) == [.clear(.queueCleared)])
        #expect(NowPlayingPlanner.actions(from: stopped, to: stopped).isEmpty)
        #expect(NowPlayingPlanner.actions(from: nil, to: stopped).isEmpty)
    }

    @Test func bufferingTheSameTrackPublishesNothing() {
        let shown = showing(sample)
        #expect(NowPlayingPlanner.actions(from: shown, to: showing(sample, playing: true)).isEmpty)
    }

    @Test func endOfQueueClearsWithItsOwnReason() {
        let shown = showing(sample)
        let stopped = showing(nil, playing: false, stop: .endOfQueue)
        #expect(NowPlayingPlanner.actions(from: shown, to: stopped) == [.clear(.endOfQueue)])
    }

    @Test func aNewTrackAfterAStopPublishesAgain() {
        let stopped = showing(nil, playing: false, stop: .queueCleared)
        let next = showing(sample)
        #expect(NowPlayingPlanner.actions(from: stopped, to: next) == [.publishIdentity])
    }

    @Test func artworkForAnotherTrackIsNotAttached() {
        let shownOther = showing(
            NowPlayingIdentity(trackID: "track-b", title: "B", artist: "Artist", album: nil, duration: 100),
            artwork: false
        )
        let nextA = showing(sample, artwork: true)
        // The new identity is published; the old track's ready flag does not
        // count as this track's artwork.
        #expect(NowPlayingPlanner.actions(from: shownOther, to: nextA) == [.publishIdentity, .attachArtwork])
    }
}

@Suite("Now Playing projection")
struct NowPlayingProjectionTests {
    @Test func playingStateCarriesIdentityAndIntent() {
        let state = NowPlayingProjection.make(
            phase: .playing,
            track: track("a", album: "Album"),
            duration: 180,
            artworkReady: false
        )
        #expect(state.identity?.trackID == "a")
        #expect(state.identity?.duration == 180)
        #expect(state.isPlaying)
        #expect(state.stopReason == nil)
    }

    @Test func loadingKeepsTheRequestedIntent() {
        let playing = NowPlayingProjection.make(
            phase: .loading(autoPlay: true), track: track("a"), duration: 0, artworkReady: false
        )
        #expect(playing.isPlaying)
        #expect(playing.identity?.trackID == "a")

        let restoring = NowPlayingProjection.make(
            phase: .loading(autoPlay: false), track: track("a"), duration: 0, artworkReady: false
        )
        #expect(!restoring.isPlaying)
    }

    @Test func aWaitingEnginePublishesAStoppedRateButKeepsIdentity() {
        let buffering = NowPlayingProjection.make(
            phase: .playing, track: track("a"), duration: 100, artworkReady: false, enginePlaying: false
        )
        #expect(!buffering.isPlaying)
        #expect(buffering.identity?.trackID == "a")
        #expect(buffering.identity?.duration == 100)

        let loading = NowPlayingProjection.make(
            phase: .loading(autoPlay: true), track: track("a"), duration: 100,
            artworkReady: false, enginePlaying: false
        )
        #expect(!loading.isPlaying)
    }

    @Test func failureKeepsTheTrackIdentity() {
        let state = NowPlayingProjection.make(
            phase: .failed("boom"), track: track("a"), duration: 100, artworkReady: false
        )
        #expect(state.identity?.trackID == "a")
        #expect(!state.isPlaying)
        #expect(state.stopReason == nil)
    }

    @Test func onlyStoppedHasAStopReason() {
        let state = NowPlayingProjection.make(
            phase: .stopped(.queueCleared), track: track("a"), duration: 100, artworkReady: true
        )
        #expect(state.identity == nil)
        #expect(state.stopReason == .queueCleared)
        #expect(!state.isPlaying)
    }

    @Test func unknownDurationStaysNil() {
        let state = NowPlayingProjection.make(
            phase: .playing, track: track("a"), duration: 0, artworkReady: false
        )
        #expect(state.identity?.duration == nil)
    }
}
