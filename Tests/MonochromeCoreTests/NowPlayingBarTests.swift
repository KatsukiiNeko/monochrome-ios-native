// NowPlayingBarTests.swift: derivation rules for the persistent now-playing bar.
import Foundation
import Testing
@testable import MonochromeCore

private func track(_ quality: AudioQuality? = .lossless) -> Track {
    Track(
        id: "stream:1",
        title: "Song",
        artist: "Artist",
        durationSeconds: 200,
        provider: "monochrome",
        streamID: "1",
        audioQuality: quality
    )
}

@Suite("NowPlayingBar")
struct NowPlayingBarTests {
    @Test func hiddenWithoutATrack() {
        #expect(NowPlayingBar.make(track: nil, state: .idle, position: 0, duration: 0) == nil)
    }

    @Test func showsTheLoadedTrackEvenWhileLoading() {
        let bar = NowPlayingBar.make(track: track(), state: .loading, position: 0, duration: 0)
        #expect(bar?.title == "Song")
        #expect(bar?.subtitle == "Artist")
        #expect(bar?.isLoading == true)
        #expect(bar?.isPlaying == false)
    }

    @Test func progressIsClampedAndZeroWithoutADuration() {
        let half = NowPlayingBar.make(track: track(), state: .playing, position: 100, duration: 200)
        #expect(half?.progress == 0.5)

        let over = NowPlayingBar.make(track: track(), state: .playing, position: 400, duration: 200)
        #expect(over?.progress == 1)

        let unknown = NowPlayingBar.make(
            track: Track(id: "x", title: "No duration", provider: "monochrome", streamID: "1"),
            state: .playing,
            position: 30,
            duration: 0
        )
        #expect(unknown?.progress == 0)
    }

    @Test func failureCarriesTheMessageAndDisablesPlaybackControls() {
        let bar = NowPlayingBar.make(track: track(), state: .failed("HTTP 403"), position: 0, duration: 200)
        #expect(bar?.failureMessage == "HTTP 403")
        #expect(bar?.isPlaying == false)
        #expect(bar?.isLoading == false)
    }

    @Test func pausedKeepsTheIdentityAndProgress() {
        let bar = NowPlayingBar.make(track: track(), state: .paused, position: 50, duration: 200)
        #expect(bar?.isPlaying == false)
        #expect(bar?.isLoading == false)
        #expect(bar?.failureMessage == nil)
        #expect(bar?.progress == 0.25)
    }

    @Test func badgePrefersTheParsedFormatAndFallsBackToTheTier() {
        let parsed = NowPlayingBar.make(
            track: track(),
            state: .playing,
            position: 0,
            duration: 200,
            format: AudioFormat(codec: "flac", bitDepth: 16, sampleRateHz: 44_100)
        )
        #expect(parsed?.badgeText == "FLAC 16/44.1")
        #expect(parsed?.badgeSpokenText == "Lossless, FLAC 16/44.1")

        let tierOnly = NowPlayingBar.make(track: track(), state: .playing, position: 0, duration: 200)
        #expect(tierOnly?.badgeText == "FLAC")

        let none = NowPlayingBar.make(track: track(nil), state: .playing, position: 0, duration: 200)
        #expect(none?.badgeText == nil)
    }
}
