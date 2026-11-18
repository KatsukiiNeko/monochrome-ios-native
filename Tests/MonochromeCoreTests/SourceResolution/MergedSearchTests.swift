// MergedSearchTests.swift: row order, dedupe, phases and the merge budget.
import Foundation
import Testing
@testable import MonochromeCore

private enum MergeFailure: Error {
    case offline
}

private func track(
    _ title: String,
    by artist: String,
    provider: MusicSourceID,
    seconds: Double? = 200
) -> Track {
    Track(
        id: "\(provider.rawValue):\(title)|\(artist)",
        title: title,
        artist: artist,
        album: "Harbour Lights",
        durationSeconds: seconds,
        provider: provider.rawValue,
        streamID: "id-\(title)"
    )
}

private let hifiNeon = track("Neon Harbour", by: "Aster Vale", provider: .monochrome)
private let hifiGold = track("Gold and Silver", by: "Aster Vale", provider: .monochrome)
private let companionNeon = track("Neon Harbour (Official Video)", by: "Aster Vale", provider: .youTubeMusic)
private let companionGold = track("Gold & Silver (Lyrics)", by: "Aster Vale", provider: .youTubeMusic)
private let companionOther = track("Static Bloom", by: "Coral Static", provider: .youTubeMusic)

@Suite("Merged search")
struct MergedSearchTests {
    @Test("HiFi rows come first and keep their order")
    func hifiFirst() {
        let merged = MergedSearch.merge(hifi: [hifiNeon, hifiGold], companion: [companionOther])
        #expect(merged.rows.first?.id == hifiNeon.id)
        #expect(merged.rows.map(\.id) == [hifiNeon.id, hifiGold.id, companionOther.id])
    }

    @Test("a companion row covered by a HiFi row is dropped")
    func dedupe() {
        let merged = MergedSearch.merge(hifi: [hifiNeon], companion: [companionNeon, companionOther])
        #expect(merged.companion.map(\.id) == [companionOther.id])
    }

    @Test("companion duplicates are dropped among themselves")
    func dedupeCompanion() {
        let copy = track("Neon Harbour", by: "Aster Vale", provider: .youTubeMusic, seconds: 201)
        let merged = MergedSearch.merge(hifi: [], companion: [companionOther, companionOther])
        #expect(merged.companion.count == 1)
        let both = MergedSearch.merge(hifi: [], companion: [companionOther, copy])
        #expect(both.companion.count == 2)
    }

    @Test("the phase follows the slower source")
    func phases() {
        #expect(MergedSearchResults(hifiStatus: .pending, companionStatus: .pending).phase == .pending)
        #expect(MergedSearchResults(hifiStatus: .complete, companionStatus: .pending).phase == .partial)
        #expect(MergedSearchResults(hifiStatus: .failed, companionStatus: .pending).phase == .partial)
        #expect(MergedSearchResults(hifiStatus: .complete, companionStatus: .complete).phase == .complete)
        #expect(MergedSearchResults(hifiStatus: .complete, companionStatus: .unconfigured).phase == .complete)
        #expect(MergedSearchResults(hifiStatus: .failed, companionStatus: .failed).phase == .failed)
    }

    @Test("the empty state needs both sources to finish empty")
    func emptyState() {
        let finished = MergedSearchResults(hifiStatus: .complete, companionStatus: .complete)
        #expect(finished.isEmpty)

        let oneFailed = MergedSearchResults(hifiStatus: .complete, companionStatus: .failed)
        #expect(!oneFailed.isEmpty)

        let pending = MergedSearchResults(hifiStatus: .complete, companionStatus: .pending)
        #expect(!pending.isEmpty)

        let neither = MergedSearchResults(hifiStatus: .failed, companionStatus: .failed)
        #expect(!neither.isEmpty)
    }

    @Test("one failure leaves the other result and a quiet note")
    func quietNote() {
        let companionFailed = MergedSearchResults(hifi: [hifiNeon], hifiStatus: .complete, companionStatus: .failed)
        #expect(companionFailed.quietNote != nil)
        #expect(companionFailed.rows.count == 1)

        let hifiFailed = MergedSearchResults(companion: [companionOther], hifiStatus: .failed, companionStatus: .complete)
        #expect(hifiFailed.quietNote != nil)
        #expect(hifiFailed.rows.count == 1)

        let unconfigured = MergedSearchResults(hifi: [hifiNeon], hifiStatus: .complete, companionStatus: .unconfigured)
        #expect(unconfigured.quietNote == nil)

        let done = MergedSearchResults(hifi: [hifiNeon], hifiStatus: .complete, companionStatus: .complete)
        #expect(done.quietNote == nil)
    }

    @Test("both searches run and merge")
    func collectBoth() async {
        let results = await MergedSearch.collect(
            hifi: { [hifiNeon, hifiGold] },
            companion: { [companionNeon, companionOther] }
        )
        #expect(results.phase == .complete)
        #expect(results.rows.count == 3)
        #expect(results.rows.first?.id == hifiNeon.id)
        #expect(results.quietNote == nil)
    }

    @Test("an unconfigured companion never takes part")
    func collectUnconfigured() async {
        let results = await MergedSearch.collect(hifi: { [hifiNeon] }, companion: nil)
        #expect(results.companionStatus == .unconfigured)
        #expect(results.phase == .complete)
        #expect(results.rows.map(\.id) == [hifiNeon.id])
        #expect(results.quietNote == nil)
    }

    @Test("a companion failure leaves the HiFi rows")
    func collectCompanionFailure() async {
        let results = await MergedSearch.collect(
            hifi: { [hifiNeon] },
            companion: { throw MergeFailure.offline }
        )
        #expect(results.hifiStatus == .complete)
        #expect(results.companionStatus == .failed)
        #expect(results.rows.map(\.id) == [hifiNeon.id])
        #expect(results.quietNote != nil)
    }

    @Test("a HiFi failure leaves the companion rows")
    func collectHiFiFailure() async {
        let results = await MergedSearch.collect(
            hifi: { throw MergeFailure.offline },
            companion: { [companionOther] }
        )
        #expect(results.hifiStatus == .failed)
        #expect(results.companionStatus == .complete)
        #expect(results.rows.map(\.id) == [companionOther.id])
        #expect(results.quietNote != nil)
    }

    @Test("a slow companion is left out instead of moving rows later")
    func collectBudget() async {
        let results = await MergedSearch.collect(
            hifi: { [hifiNeon] },
            companion: {
                try? await Task.sleep(for: .milliseconds(300))
                return [companionOther]
            },
            budget: .milliseconds(20)
        )
        #expect(results.hifiStatus == .complete)
        #expect(results.companionStatus == .failed)
        #expect(results.rows.map(\.id) == [hifiNeon.id])
        #expect(results.phase == .partial)
    }

    @Test("two empty searches show the empty state")
    func collectEmpty() async {
        let results = await MergedSearch.collect(hifi: { [] }, companion: { [] })
        #expect(results.isEmpty)
        #expect(results.phase == .complete)
    }
}
