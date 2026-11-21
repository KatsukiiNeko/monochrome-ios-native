// TurntablePlannerTests.swift: snapshot to timeline frames, and the reload budget.
import Foundation
import Testing
@testable import MonochromeCore

@Suite("Turntable planner")
struct TurntablePlannerTests {
    let start = Date(timeIntervalSince1970: 1_000_000)
    let planner = TurntablePlanner()

    func playing(
        duration: Double = 200,
        position: Double = 0,
        written: TimeInterval = 0,
        started: TimeInterval? = nil
    ) -> PlaybackSnapshot {
        PlaybackSnapshot(
            trackID: "t1",
            title: "Song",
            artist: "Artist",
            duration: duration,
            position: position,
            isPlaying: true,
            platterDegrees: 40,
            date: start.addingTimeInterval(written),
            playStartedAt: started.map { start.addingTimeInterval($0) }
        )
    }

    @Test func pausedSnapshotGivesOneStoppedFrame() {
        var s = playing(position: 50)
        s.isPlaying = false
        let frames = planner.frames(for: s, now: start, mode: .spin)
        #expect(frames.count == 1)
        #expect(frames[0].platterDegrees == 40)
        #expect(frames[0].lift == 0)
        #expect(abs(frames[0].armRotation - planner.geometry.armRotation(progress: 0.25)) < 1e-9)
    }

    @Test func stillModeGivesOneFrame() {
        let frames = planner.frames(for: playing(), now: start, mode: .still)
        #expect(frames.count == 1)
        #expect(frames[0].lift == 0)
    }

    @Test func playingSnapshotGivesIncreasingStepsThatEndWithTheSong() {
        let frames = planner.frames(for: playing(), now: start, mode: .spin)
        #expect(frames.count == 100)
        #expect(frames.count <= planner.maxFrames)
        var lastPlatter = -Double.infinity
        var lastArm = -Double.infinity
        for (index, frame) in frames.enumerated() {
            if index > 0 {
                #expect(frame.date.timeIntervalSince(frames[index - 1].date) == planner.step)
            }
            #expect(frame.platterDegrees > lastPlatter)
            #expect(frame.armRotation >= lastArm)
            lastPlatter = frame.platterDegrees
            lastArm = frame.armRotation
            #expect(frame.lift == 0)
        }
        #expect(frames.last!.date < start.addingTimeInterval(200))
    }

    @Test func trackStartShowsTheDropThenTracks() {
        let frames = planner.frames(
            for: playing(started: -1),
            now: start,
            mode: .spin
        )
        #expect(frames[0].lift == 1)
        #expect(frames[0].armRotation == 0)
        #expect(frames[1].lift == 1)
        #expect(frames[2].lift == 0)
    }

    @Test func aTrackThatStartedLongAgoHasNoDropFrames() {
        let frames = planner.frames(for: playing(started: -60), now: start, mode: .spin)
        #expect(frames.allSatisfy { $0.lift == 0 })
    }

    @Test func aLateTimelinePicksUpTheArmMidDrop() {
        // A reload three seconds in must not restart the drop or miss it.
        let frames = planner.frames(for: playing(started: -3), now: start, mode: .spin)
        #expect(frames[0].lift == 1)
        #expect(frames[0].armRotation > 0)
        #expect(frames[1].lift == 0)
    }

    @Test func nothingLoadedIsParkedAndLifted() {
        let frames = planner.frames(for: .nothingPlaying, now: start, mode: .spin)
        #expect(frames.count == 1)
        #expect(frames[0].armRotation == 0)
        #expect(frames[0].lift == 1)
    }

    @Test func aSongAboutToEndStillGivesTheEndPose() {
        let frames = planner.frames(for: playing(duration: 10, position: 10), now: start, mode: .spin)
        #expect(frames.count == 1)
        #expect(abs(frames[0].armRotation - planner.geometry.armRotation(progress: 1)) < 1e-9)
    }

    @Test func aLaterSnapshotContinuesTheSamePlatterAngle() throws {
        let first = playing(duration: 400)
        let old = planner.frames(for: first, now: start, mode: .spin)
        let laterDate = start.addingTimeInterval(10)
        var second = first
        second.date = laterDate
        second.position = 10
        second.platterDegrees = first.platter(at: laterDate)
        let new = planner.frames(for: second, now: laterDate, mode: .spin)

        let oldByDate = Dictionary(uniqueKeysWithValues: old.map { ($0.date, $0.platterDegrees) })
        for frame in new where oldByDate[frame.date] != nil {
            #expect(abs(frame.platterDegrees - oldByDate[frame.date]!) < 1e-6)
        }
        #expect(new[0].platterDegrees >= old[0].platterDegrees)
    }
}

@Suite("Playback snapshot")
struct PlaybackSnapshotTests {
    let start = Date(timeIntervalSince1970: 900_000)

    @Test func elapsedExtrapolatesOnlyWhilePlayingAndClampsToDuration() {
        var s = PlaybackSnapshot(trackID: "t", duration: 30, position: 10, isPlaying: true, date: start)
        #expect(s.elapsed(at: start.addingTimeInterval(5)) == 15)
        #expect(s.elapsed(at: start.addingTimeInterval(60)) == 30)
        s.isPlaying = false
        #expect(s.elapsed(at: start.addingTimeInterval(5)) == 10)
    }

    @Test func platterOnlyTurnsDuringPlayback() {
        var s = PlaybackSnapshot(trackID: "t", isPlaying: true, platterDegrees: 12, date: start)
        #expect(s.platter(at: start.addingTimeInterval(3)) == 612)
        s.isPlaying = false
        #expect(s.platter(at: start.addingTimeInterval(3)) == 12)
    }
}

@Suite("Snapshot store")
struct SnapshotStoreTests {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("monochrome-snapshot-\(UUID().uuidString)")

    @Test func roundTripAndCorruptFile() throws {
        let store = SnapshotStore(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshot = PlaybackSnapshot(
            trackID: "t1", title: "Song", artist: "Artist", duration: 100,
            position: 5, isPlaying: true, platterDegrees: 90,
            date: Date(timeIntervalSince1970: 1), artworkFile: "artwork-t1.jpg"
        )
        try store.write(snapshot)
        #expect(store.read() == snapshot)

        try Data("not json".utf8).write(to: directory.appendingPathComponent(SnapshotStore.snapshotFile))
        #expect(store.read() == nil)
    }

    @Test func aMissingContainerFailsWriteButReadsNil() {
        let store = SnapshotStore(directory: nil)
        #expect(store.read() == nil)
        #expect(throws: SnapshotStore.StoreError.noContainer) {
            try store.write(.nothingPlaying)
        }
    }

    @Test func artworkPruneKeepsOnlyTheNewestNames() throws {
        let store = SnapshotStore(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in ["artwork-1.jpg", "artwork-2.jpg", "artwork-3.jpg", "other.txt"] {
            try store.writeArtwork(Data(name.utf8), named: name)
        }
        store.pruneArtwork(keeping: ["artwork-2.jpg", "artwork-3.jpg"])
        let left = try Set(FileManager.default.contentsOfDirectory(atPath: directory.path))
        #expect(left == ["artwork-2.jpg", "artwork-3.jpg", "other.txt"])
    }
}

@Suite("Reload governor")
struct ReloadGovernorTests {
    @Test func firstRequestIsNowAndTheNextIsCoalesced() {
        var governor = ReloadGovernor()
        let t0 = Date(timeIntervalSince1970: 10_000)
        #expect(governor.request(at: t0) == .now)
        #expect(governor.request(at: t0.addingTimeInterval(1)) == .later(t0.addingTimeInterval(5)))
        #expect(governor.request(at: t0.addingTimeInterval(6)) == .now)
    }

    @Test func anUrgentRequestIgnoresTheBudget() {
        var governor = ReloadGovernor()
        let t0 = Date(timeIntervalSince1970: 10_000)
        #expect(governor.request(at: t0) == .now)
        #expect(governor.request(at: t0.addingTimeInterval(1), urgent: true) == .now)
        // The urgent reload also resets the window for ordinary requests.
        #expect(governor.request(at: t0.addingTimeInterval(2)) == .later(t0.addingTimeInterval(6)))
    }
}
