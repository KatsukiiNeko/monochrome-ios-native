// StallPolicyTests.swift: the rows of the stall recovery decision.
import Testing
@testable import MonochromeCore

private func facts(
    item: ItemStatus = .ready,
    time: TimeControl,
    keepUp: Bool = true,
    empty: Bool = false
) -> EngineFacts {
    EngineFacts(itemStatus: item, timeControl: time, likelyToKeepUp: keepUp, bufferEmpty: empty)
}

@Suite("Stall policy")
struct StallPolicyTests {
    @Test func noIntentMeansNoAction() {
        #expect(StallPolicy.decide(wantsToPlay: false, facts: facts(time: .waiting), stalledFor: 30, reloads: 0) == .none)
    }

    @Test func playingFactsNeedNoAction() {
        #expect(StallPolicy.decide(wantsToPlay: true, facts: facts(time: .playing), stalledFor: 30, reloads: 0) == .none)
    }

    @Test func waitingShowsBufferingThenReloads() {
        #expect(StallPolicy.decide(wantsToPlay: true, facts: facts(time: .waiting), stalledFor: 2, reloads: 0) == .showBuffering)
        #expect(StallPolicy.decide(wantsToPlay: true, facts: facts(time: .waiting), stalledFor: 9, reloads: 0) == .reloadFromPosition)
        #expect(StallPolicy.decide(wantsToPlay: true, facts: facts(time: .waiting), stalledFor: 9, reloads: 2) == .fail)
    }

    @Test func pausedFactsRetryPlayThenReload() {
        #expect(StallPolicy.decide(wantsToPlay: true, facts: facts(time: .paused), stalledFor: 1, reloads: 0) == .none)
        #expect(StallPolicy.decide(wantsToPlay: true, facts: facts(time: .paused), stalledFor: 2, reloads: 0) == .retryPlay)
        #expect(StallPolicy.decide(wantsToPlay: true, facts: facts(time: .paused), stalledFor: 4, reloads: 0) == .reloadFromPosition)
        #expect(StallPolicy.decide(wantsToPlay: true, facts: facts(time: .paused), stalledFor: 4, reloads: 2) == .fail)
    }

    @Test func failedItemReloadsTwiceThenFails() {
        #expect(StallPolicy.decide(wantsToPlay: true, facts: facts(item: .failed, time: .paused), stalledFor: 1, reloads: 0) == .reloadFromPosition)
        #expect(StallPolicy.decide(wantsToPlay: true, facts: facts(item: .failed, time: .paused), stalledFor: 1, reloads: 1) == .reloadFromPosition)
        #expect(StallPolicy.decide(wantsToPlay: true, facts: facts(item: .failed, time: .paused), stalledFor: 1, reloads: 2) == .fail)
    }

    @Test func onlyProducingAudioCountsAsPlaying() {
        #expect(facts(time: .playing).isProducingAudio)
        #expect(!facts(time: .waiting).isProducingAudio)
        #expect(!facts(item: .failed, time: .playing).isProducingAudio)
    }
}
