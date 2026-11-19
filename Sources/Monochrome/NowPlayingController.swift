// NowPlayingController.swift: Lock Screen metadata and remote transport commands.
#if canImport(MediaPlayer)
import MediaPlayer
import MonochromeCore
import UIKit

/// Publishes the player's state to the system now-playing surface. One pump
/// observes the player and hands the outcome to `NowPlayingPlanner`, so the
/// same state always produces the same writes, and nothing clears the surface
/// except an explicit stop.
@MainActor
final class NowPlayingController {
    /// How often the elapsed-time anchor is refreshed while playing. iOS
    /// extrapolates between writes, so this only trims accumulated drift.
    private static let driftInterval: TimeInterval = 10

    private let player: PlayerController
    private let artworkURL: (Track) -> URL?
    private let commandRelay = CallbackRelay<RemoteCommand>()

    private var pumpTask: Task<Void, Never>?
    private var wake: AsyncStream<Void>.Continuation?
    /// What the system currently shows; the planner diffs against it.
    private var published: NowPlayingState?
    private var lastPublishAt = Date.distantPast
    private var lastPublishedSeek = 0

    private var artworkTask: Task<Void, Never>?
    private var artworkTrackID: String?
    private var artworkImage: MPMediaItemArtwork?

    /// The commands this instance registered, so only they are removed.
    private var commandTargets: [(MPRemoteCommand, Any)] = []

    init(player: PlayerController, artworkURL: @escaping (Track) -> URL? = { $0.artworkURL }) {
        self.player = player
        self.artworkURL = artworkURL
        commandRelay.handler = { [weak self] command in self?.handle(command) }
    }

    // MARK: - Lifecycle

    func start() {
        guard pumpTask == nil else { return }
        registerCommands()
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        wake = continuation
        nowPlayingLog.notice("start")
        pumpTask = Task { [weak self] in
            await self?.pump(stream)
        }
    }

    func stop() {
        pumpTask?.cancel()
        pumpTask = nil
        wake?.finish()
        wake = nil
        artworkTask?.cancel()
        artworkTask = nil
        unregisterCommands()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        published = nil
        nowPlayingLog.notice("stop")
    }

    // MARK: - Observation pump

    private struct Inputs {
        var phase: PlaybackState
        var track: Track?
        var duration: Double
        var position: Double
        var canNext: Bool
        var canPrevious: Bool
        var seekCount: Int
    }

    /// One loop: arm the observation, publish what it read, then wait for the
    /// next change or the drift timer. Publishing after arming means a change
    /// that lands mid-publish still wakes the next pass.
    private func pump(_ stream: AsyncStream<Void>) async {
        while !Task.isCancelled {
            let (wake, next) = (self.wake, stream)
            var inputs: Inputs?
            withObservationTracking {
                inputs = read()
            } onChange: {
                wake?.yield(())
            }
            let drift = Task {
                try? await Task.sleep(for: .seconds(Self.driftInterval))
                guard !Task.isCancelled else { return }
                wake?.yield(())
            }
            if let inputs { publish(inputs) }
            for await _ in next { break }
            drift.cancel()
        }
    }

    private func read() -> Inputs {
        Inputs(
            phase: player.state,
            track: player.currentTrack,
            duration: player.duration,
            position: player.position,
            canNext: player.queue.canAdvance,
            canPrevious: player.queue.canRewind,
            seekCount: player.seekCount
        )
    }

    private func publish(_ inputs: Inputs) {
        let next = NowPlayingProjection.make(
            phase: inputs.phase,
            track: inputs.track,
            duration: inputs.duration,
            artworkReady: artworkTrackID == inputs.track?.id && artworkImage != nil
        )
        var actions = NowPlayingPlanner.actions(from: published, to: next)

        // A seek changes no visible text, and iOS needs a fresh anchor for it.
        let seeked = inputs.seekCount != lastPublishedSeek
        let drifted = next.isPlaying && Date().timeIntervalSince(lastPublishAt) >= Self.driftInterval
        if (seeked || drifted), next.identity != nil, !actions.contains(.publishIdentity) {
            actions.append(.updatePlaybackState)
        }

        for action in actions {
            apply(action, showing: next, inputs: inputs)
        }
        if !actions.isEmpty {
            published = next
            lastPublishedSeek = inputs.seekCount
            lastPublishAt = Date()
        }
        updateCommandAvailability(inputs)
    }

    // MARK: - Writing the surface

    private func apply(_ action: NowPlayingAction, showing state: NowPlayingState, inputs: Inputs) {
        let center = MPNowPlayingInfoCenter.default()
        switch action {
        case .publishIdentity:
            guard let identity = state.identity else { return }
            loadArtworkIfNeeded(for: inputs.track)
            center.nowPlayingInfo = info(for: state, inputs: inputs)
            center.playbackState = playbackState(state)
            nowPlayingLog.notice(
                "publish track=\(identity.trackID, privacy: .public) playing=\(state.isPlaying, privacy: .public) duration=\(identity.duration ?? -1, privacy: .public)"
            )
        case .updatePlaybackState:
            guard var info = center.nowPlayingInfo else {
                center.nowPlayingInfo = info(for: state, inputs: inputs)
                return
            }
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = inputs.position
            info[MPNowPlayingInfoPropertyPlaybackRate] = state.isPlaying ? 1.0 : 0.0
            center.nowPlayingInfo = info
            center.playbackState = playbackState(state)
        case .attachArtwork:
            guard let image = artworkImage, var info = center.nowPlayingInfo else { return }
            info[MPMediaItemPropertyArtwork] = image
            center.nowPlayingInfo = info
            nowPlayingLog.notice("artwork attached")
        case .clear(let reason):
            artworkTask?.cancel()
            artworkTask = nil
            artworkImage = nil
            artworkTrackID = nil
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            nowPlayingLog.notice("clear reason=\(reason.rawValue, privacy: .public)")
        }
    }

    private func info(for state: NowPlayingState, inputs: Inputs) -> [String: Any] {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: state.identity?.title ?? "",
            MPMediaItemPropertyArtist: state.identity?.artist ?? "",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: inputs.position,
            MPNowPlayingInfoPropertyPlaybackRate: state.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let album = state.identity?.album {
            info[MPMediaItemPropertyAlbumTitle] = album
        }
        if let duration = state.identity?.duration {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        if let artworkImage, artworkTrackID == state.identity?.trackID {
            info[MPMediaItemPropertyArtwork] = artworkImage
        }
        return info
    }

    private func playbackState(_ state: NowPlayingState) -> MPNowPlayingPlaybackState {
        guard state.identity != nil else { return .stopped }
        return state.isPlaying ? .playing : .paused
    }

    /// Loads one artwork image per track. A failed image is not retried until the
    /// track changes, so a missing catalog image does not cause a request storm.
    private func loadArtworkIfNeeded(for track: Track?) {
        guard let track, artworkTrackID != track.id else { return }
        artworkTrackID = track.id
        artworkImage = nil
        artworkTask?.cancel()
        guard let url = artworkURL(track) else { return }

        artworkTask = Task { [weak self] in
            let data: Data?
            if url.isFileURL {
                data = try? Data(contentsOf: url)
            } else {
                data = try? await URLSession.shared.data(from: url).0
            }
            guard !Task.isCancelled, let data, let image = UIImage(data: data) else { return }
            guard let self, self.artworkTrackID == track.id else { return }
            self.artworkImage = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            self.wake?.yield(())
        }
    }

    // MARK: - Remote commands

    private func updateCommandAvailability(_ inputs: Inputs) {
        let snapshot = NowPlayingSnapshot.make(
            track: inputs.track,
            state: inputs.phase,
            position: inputs.position,
            duration: inputs.duration,
            hasNext: inputs.canNext,
            hasPrevious: inputs.canPrevious
        )
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = snapshot.canPlay
        center.pauseCommand.isEnabled = snapshot.canPause
        center.togglePlayPauseCommand.isEnabled = snapshot.canPlay || snapshot.canPause
        center.nextTrackCommand.isEnabled = snapshot.canNext
        center.previousTrackCommand.isEnabled = snapshot.canPrevious
        center.changePlaybackPositionCommand.isEnabled = snapshot.canSeek
    }

    private func registerCommands() {
        let center = MPRemoteCommandCenter.shared()
        func register(_ command: MPRemoteCommand, _ make: @escaping (MPRemoteCommandEvent) -> RemoteCommand?) {
            let relay = commandRelay
            let token = command.addTarget { event in
                guard let command = make(event) else { return .commandFailed }
                relay.send(command)
                return .success
            }
            commandTargets.append((command, token))
        }
        register(center.playCommand) { _ in .play }
        register(center.pauseCommand) { _ in .pause }
        register(center.togglePlayPauseCommand) { _ in .toggle }
        register(center.nextTrackCommand) { _ in .next }
        register(center.previousTrackCommand) { _ in .previous }
        register(center.changePlaybackPositionCommand) { event in
            guard let seek = event as? MPChangePlaybackPositionCommandEvent else { return nil }
            return .seek(seek.positionTime)
        }
    }

    private func unregisterCommands() {
        for (command, token) in commandTargets {
            command.removeTarget(token)
        }
        commandTargets.removeAll()
    }

    private func handle(_ command: RemoteCommand) {
        Task {
            await perform(command, on: player)
        }
    }
}
#endif
