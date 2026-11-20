// ListenAccumulatorTests.swift: time heard, not playhead position.
import Testing
@testable import MonochromeCore

@Suite("Listen accumulator")
struct ListenAccumulatorTests {
    @Test func countsOnlyPlayingTicks() {
        var listened = ListenAccumulator()
        listened.tick(position: 1, isPlaying: true)
        listened.tick(position: 2, isPlaying: true)
        listened.tick(position: 3, isPlaying: false)
        listened.tick(position: 4, isPlaying: false)
        listened.tick(position: 5, isPlaying: true)
        #expect(listened.seconds == 2)
    }

    @Test func aSeekIsNotListening() {
        var listened = ListenAccumulator()
        listened.tick(position: 1, isPlaying: true)
        listened.tick(position: 60, isPlaying: true)
        #expect(listened.seconds == 0)
    }

    @Test func fractionClampsAndHandlesUnknownDuration() {
        var listened = ListenAccumulator()
        listened.tick(position: 1, isPlaying: true)
        listened.tick(position: 2, isPlaying: true)
        #expect(listened.fraction(of: 4) == 0.25)
        #expect(listened.fraction(of: 0) == 0)
        listened.tick(position: 3, isPlaying: true)
        listened.tick(position: 4, isPlaying: true)
        listened.tick(position: 5, isPlaying: true)
        listened.tick(position: 6, isPlaying: true)
        #expect(listened.fraction(of: 4) == 1)
    }

    @Test func halfHeardSwitchesToCompletion() {
        var listened = ListenAccumulator()
        for second in 1...49 {
            listened.tick(position: Double(second), isPlaying: true)
        }
        #expect(StreamStoragePolicy.decide(listened: listened, duration: 100) == .keepBuffering)
        listened.tick(position: 51, isPlaying: true)
        #expect(StreamStoragePolicy.decide(listened: listened, duration: 100) == .completeAndPromote)
    }

    @Test func unknownDurationStaysBuffering() {
        var listened = ListenAccumulator()
        listened.tick(position: 1, isPlaying: true)
        #expect(StreamStoragePolicy.decide(listened: listened, duration: nil) == .keepBuffering)
    }

    @Test func resetForgetsEverything() {
        var listened = ListenAccumulator()
        listened.tick(position: 1, isPlaying: true)
        listened.tick(position: 2, isPlaying: true)
        listened.reset()
        listened.tick(position: 3, isPlaying: true)
        #expect(listened.seconds == 0)
    }
}
