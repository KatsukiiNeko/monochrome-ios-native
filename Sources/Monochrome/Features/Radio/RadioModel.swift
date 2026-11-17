// RadioModel.swift: starts a radio and keeps its queue filled.
#if canImport(SwiftUI)
import Foundation
import MonochromeCore
import Observation

/// Drives the radio engine from the views: starts a radio for a track, artist
/// or album and asks for more tracks when the queue runs low.
@MainActor
@Observable
final class RadioModel {
    @ObservationIgnored private let player: PlayerController
    @ObservationIgnored private let engine: RadioEngine
    @ObservationIgnored private var isToppingUp = false

    init(
        player: PlayerController,
        search: @escaping RadioSearch,
        recents: @escaping () -> [Track]
    ) {
        self.player = player
        self.engine = RadioEngine(
            search: search,
            // The newest plays are the ones a radio must not repeat.
            recentKeys: { recents().map(\.sourceKey) }
        )
    }

    var isRunning: Bool { engine.isRunning }

    /// Starts a radio and plays it; a track seed plays first.
    func start(_ seed: RadioSeed) {
        Task {
            let tracks = await engine.start(seed: seed)
            guard !tracks.isEmpty else { return }
            await player.play(tracks: tracks, startingAt: 0)
        }
    }

    /// Ends the radio; the queue stays as it is.
    func stop() {
        engine.stop()
    }

    /// Called when the player moves to another track: ends the radio when the
    /// listener left it and tops it up when the queue runs low.
    func trackChanged() {
        guard engine.isRunning else { return }
        guard let current = player.currentTrack, engine.owns(current) else {
            engine.stop()
            return
        }
        let remaining = player.queue.tracks.count - (player.queue.currentIndex ?? 0) - 1
        guard RadioEngine.needsTopUp(remaining: remaining), !isToppingUp else { return }
        isToppingUp = true
        Task {
            defer { isToppingUp = false }
            let more = await engine.topUp(queued: player.queue.tracks)
            player.append(more)
        }
    }
}
#endif
