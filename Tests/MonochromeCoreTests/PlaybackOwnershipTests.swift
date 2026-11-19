// PlaybackOwnershipTests.swift: token fencing and the engine load arbiter.
import Testing
@testable import MonochromeCore

@Suite("Playback ownership")
struct PlaybackOwnershipTests {
    @Test func newestTokenOwnsPlayback() {
        var ownership = PlaybackOwnership()
        let first = ownership.begin()
        let second = ownership.begin()
        #expect(!ownership.owns(first))
        #expect(ownership.owns(second))
    }

    @Test func invalidateAllKillsEveryToken() {
        var ownership = PlaybackOwnership()
        let token = ownership.begin()
        ownership.invalidateAll()
        #expect(!ownership.owns(token))
    }

    @Test func tokensCompareByOrder() {
        var ownership = PlaybackOwnership()
        let first = ownership.begin()
        let second = ownership.begin()
        #expect(first < second)
    }

    @Test func arbiterRejectsAnOlderLoad() {
        var arbiter = PlaybackLoadArbiter()
        let acceptedTwo = arbiter.accept(PlaybackToken(value: 2))
        let acceptedOne = arbiter.accept(PlaybackToken(value: 1))
        #expect(acceptedTwo)
        #expect(!acceptedOne)
        #expect(arbiter.owns(PlaybackToken(value: 2)))
        #expect(!arbiter.owns(PlaybackToken(value: 1)))
    }

    @Test func arbiterAcceptsTheSameTokenAgain() {
        var arbiter = PlaybackLoadArbiter()
        let first = arbiter.accept(PlaybackToken(value: 3))
        let second = arbiter.accept(PlaybackToken(value: 3))
        #expect(first)
        #expect(second)
        #expect(arbiter.owns(PlaybackToken(value: 3)))
    }
}
