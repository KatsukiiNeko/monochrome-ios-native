// NowPlayingController.swift: Lock Screen metadata and remote transport commands.
#if canImport(MediaPlayer)
import MediaPlayer
import MonochromeCore

@MainActor
final class NowPlayingController {
    private let player: PlayerController
    private let invalidated = CallbackRelay<Void>()
    private let seekRelay = CallbackRelay<Double>()
    private let commandRelay = CallbackRelay<RemoteCommand>()

    init(player: PlayerController) {
        self.player = player
        invalidated.handler = { [weak self] _ in self?.observe() }
        commandRelay.handler = { [weak self] command in self?.handle(command) }
        seekRelay.handler = { [weak self] time in self?.player.seek(to: time) }
        configureCommands()
        observe()
    }

    // MARK: - Metadata

    /// Re-registers after every change; the player is the single source of truth.
    private func observe() {
        withObservationTracking {
            applyMetadata()
        } onChange: { [invalidated] in
            invalidated.send(())
        }
    }

    private func applyMetadata() {
        guard let track = player.currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.displayArtist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player.position,
            MPNowPlayingInfoPropertyPlaybackRate: player.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
        ]
        if player.duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = player.duration
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Remote commands

    private func configureCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [commandRelay] _ in
            commandRelay.send(.play)
            return .success
        }
        center.pauseCommand.addTarget { [commandRelay] _ in
            commandRelay.send(.pause)
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [commandRelay] _ in
            commandRelay.send(.toggle)
            return .success
        }
        center.nextTrackCommand.addTarget { [commandRelay] _ in
            commandRelay.send(.next)
            return .success
        }
        center.previousTrackCommand.addTarget { [commandRelay] _ in
            commandRelay.send(.previous)
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [seekRelay] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            seekRelay.send(event.positionTime)
            return .success
        }
    }

    private func handle(_ command: RemoteCommand) {
        Task {
            switch command {
            case .play:
                if !player.isPlaying { await player.togglePlayPause() }
            case .pause:
                if player.isPlaying { await player.togglePlayPause() }
            case .toggle:
                await player.togglePlayPause()
            case .next:
                await player.next()
            case .previous:
                await player.previous()
            }
        }
    }
}

enum RemoteCommand: Sendable {
    case play, pause, toggle, next, previous
}
#endif
