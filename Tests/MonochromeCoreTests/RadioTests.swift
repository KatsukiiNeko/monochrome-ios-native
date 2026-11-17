// RadioTests.swift: the radio seed, the top-up rule and the recent-play skip.
import Foundation
import Testing
@testable import MonochromeCore

private func track(_ id: String, artist: String = "Artist", title: String? = nil) -> Track {
    Track(
        id: Track.remoteIDPrefix + id,
        title: title ?? "Song \(id)",
        artist: artist,
        provider: "monochrome",
        streamID: id
    )
}

@MainActor
@Suite("Radio")
struct RadioTests {
    @Test("the seed asks the catalog for the artist of a track")
    func seedQuery() {
        #expect(RadioSeed.track(track("a", artist: "Loved")).query == "Loved")
        #expect(RadioSeed.artist("Loved").query == "Loved")
        #expect(RadioSeed.album("Discovery").query == "Discovery")
        #expect(RadioSeed.track(track("b", artist: "")).query == "Song b")
    }

    @Test("a radio starts with the tracks of its seed")
    func startFillsTheQueue() async {
        let engine = RadioEngine(search: { _ in [track("1"), track("2")] }, recentKeys: { [] })
        let tracks = await engine.start(seed: .artist("Loved"))

        #expect(engine.isRunning)
        #expect(tracks.map(\.id) == [Track.remoteIDPrefix + "1", Track.remoteIDPrefix + "2"])
        #expect(engine.owns(tracks[0]))
    }

    @Test("a track seed stays the first track and is not repeated")
    func seedTrackIsKept() async {
        let seed = track("a", artist: "Loved")
        let engine = RadioEngine(search: { _ in [seed, track("b")] }, recentKeys: { [] })
        let tracks = await engine.start(seed: .track(seed))

        #expect(tracks.map(\.id) == [seed.id, Track.remoteIDPrefix + "b"])
        #expect(engine.owns(seed))
    }

    @Test("a track played in the last fifty plays is skipped")
    func recentPlaysAreSkipped() async {
        let recent = track("1")
        let engine = RadioEngine(
            search: { _ in [recent, track("2")] },
            recentKeys: { [recent.sourceKey] }
        )
        let tracks = await engine.start(seed: .artist("Loved"))

        #expect(tracks.map(\.id) == [Track.remoteIDPrefix + "2"])
    }

    @Test("a track already in the queue is not added again")
    func queuedTracksAreSkipped() async {
        let engine = RadioEngine(search: { _ in [track("1"), track("2")] }, recentKeys: { [] })
        _ = await engine.start(seed: .artist("Loved"))
        let added = await engine.topUp(queued: [track("1")])

        #expect(added.isEmpty)
    }

    @Test("a top-up adds fresh tracks only")
    func topUpAddsNewTracks() async {
        let engine = RadioEngine(
            search: { _ in [track("1"), track("2"), track("3")] },
            recentKeys: { [] }
        )
        _ = await engine.start(seed: .artist("Loved"))
        let added = await engine.topUp(queued: [])

        #expect(added.isEmpty, "the first batch already used every candidate")
    }

    @Test("the queue is topped up when three tracks or fewer are left")
    func topUpThreshold() {
        #expect(RadioEngine.needsTopUp(remaining: 3))
        #expect(RadioEngine.needsTopUp(remaining: 0))
        #expect(RadioEngine.needsTopUp(remaining: 4) == false)
    }

    @Test("a radio stops when the queue is replaced")
    func stopEndsTheRadio() async {
        let engine = RadioEngine(search: { _ in [track("1")] }, recentKeys: { [] })
        _ = await engine.start(seed: .artist("Loved"))
        #expect(engine.isRunning)

        engine.stop()

        #expect(engine.isRunning == false)
        #expect(engine.seed == nil)
        #expect(engine.owns(track("1")) == false)
    }

    @Test("a failing search leaves the radio running with an error")
    func searchFailure() async {
        let engine = RadioEngine(
            search: { _ in throw RadioTestError.failed },
            recentKeys: { [] }
        )
        let tracks = await engine.start(seed: .artist("Loved"))

        #expect(tracks.isEmpty)
        #expect(engine.isRunning)
        #expect(engine.lastError != nil)
    }
}

private enum RadioTestError: Error {
    case failed
}
