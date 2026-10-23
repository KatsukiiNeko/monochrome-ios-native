// NowPlayingController.swift: Lock Screen metadata and remote transport commands.
#if canImport(MediaPlayer)
import MediaPlayer
import MonochromeCore
import UIKit

@MainActor
final class NowPlayingController {
    private let player: PlayerController
    private let artworkURL: (Track) -> URL?
    private let invalidated = CallbackRelay<Void>()
    private let seekRelay = CallbackRelay<Double>()
    private let commandRelay = CallbackRelay<RemoteCommand>()

    private var artworkTask: Task<Void, Never>?
    private var artworkTrackID: String?
    private var artwork: MPMediaItemArtwork?

    init(player: PlayerController, artworkURL: @escaping (Track) -> URL? = { $0.artworkURL }) {
        self.player = player
        self.artworkURL = artworkURL
        invalidated.handler = { [weak self] _ in self?.observe() }
        commandRelay.handler = { [weak self] command in self?.handle(command) }
        seekRelay.handler = { [weak self] time in self?.player.seek(to: time) }
        configureCommands()
        observe()
    }

    deinit {
        // The feature owns these commands for the app's lifetime; removing all
        // targets here prevents a stale controller from answering later.
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.removeTarget(nil)
    }

    // MARK: - Metadata

    /// Re-registers after every player change; the player remains the single source.
    private func observe() {
        withObservationTracking {
            applyMetadata()
        } onChange: { [invalidated] in
            invalidated.send(())
        }
    }

    private func applyMetadata() {
        guard let track = player.currentTrack else {
            artworkTask?.cancel()
            artworkTask = nil
            artworkTrackID = nil
            artwork = nil
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            MPNowPlayingInfoCenter.default().playbackState = .stopped
            updateCommandAvailability(hasTrack: false)
            return
        }

        loadArtworkIfNeeded(for: track)

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.displayArtist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player.position,
            MPNowPlayingInfoPropertyPlaybackRate: player.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if !track.album.isEmpty {
            info[MPMediaItemPropertyAlbumTitle] = track.album
        }
        if player.duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = player.duration
        }
        if let artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = player.isPlaying ? .playing : .paused
        updateCommandAvailability(hasTrack: true)
    }

    /// Loads one artwork image per track. A failed image is not retried until the
    /// track changes, so a missing catalog image does not cause a request storm.
    private func loadArtworkIfNeeded(for track: Track) {
        guard artworkTrackID != track.id else { return }
        artworkTrackID = track.id
        artwork = nil
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
            self.artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            self.applyMetadata()
        }
    }

    private func updateCommandAvailability(hasTrack: Bool) {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = hasTrack && !player.isPlaying
        center.pauseCommand.isEnabled = hasTrack && player.isPlaying
        center.togglePlayPauseCommand.isEnabled = hasTrack
        center.nextTrackCommand.isEnabled = hasTrack
        center.previousTrackCommand.isEnabled = hasTrack
        center.changePlaybackPositionCommand.isEnabled = hasTrack && player.duration > 0
    }

    // MARK: - Remote commands

    private func configureCommands() {
        let center = MPRemoteCommandCenter.shared()
        // Idempotent: a second controller must not leave two handlers behind.
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.removeTarget(nil)

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
