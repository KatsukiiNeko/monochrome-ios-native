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
    private let commandRelay = CallbackRelay<RemoteCommand>()

    private var artworkTask: Task<Void, Never>?
    private var artworkTrackID: String?
    private var artwork: MPMediaItemArtwork?

    init(player: PlayerController, artworkURL: @escaping (Track) -> URL? = { $0.artworkURL }) {
        self.player = player
        self.artworkURL = artworkURL
        invalidated.handler = { [weak self] _ in self?.observe() }
        commandRelay.handler = { [weak self] command in self?.handle(command) }
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
            updateCommandAvailability(NowPlayingSnapshot.make(
                track: nil,
                state: player.state,
                position: 0,
                duration: 0,
                hasNext: false,
                hasPrevious: false
            ))
            return
        }

        loadArtworkIfNeeded(for: track)
        let snapshot = NowPlayingSnapshot.make(
            track: track,
            state: player.state,
            position: player.position,
            duration: player.duration,
            hasNext: player.queue.canAdvance,
            hasPrevious: player.queue.canRewind
        )

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: snapshot.title,
            MPMediaItemPropertyArtist: snapshot.artist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: snapshot.elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: snapshot.rate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if !snapshot.album.isEmpty {
            info[MPMediaItemPropertyAlbumTitle] = snapshot.album
        }
        if snapshot.duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = snapshot.duration
        }
        if let artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        switch snapshot.playbackState {
        case .playing: MPNowPlayingInfoCenter.default().playbackState = .playing
        case .paused: MPNowPlayingInfoCenter.default().playbackState = .paused
        case .stopped: MPNowPlayingInfoCenter.default().playbackState = .stopped
        }
        updateCommandAvailability(snapshot)
        player.log?("nowplaying publish track=\(track.id) state=\(snapshot.playbackState) next=\(snapshot.canNext) previous=\(snapshot.canPrevious)")
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

    private func updateCommandAvailability(_ snapshot: NowPlayingSnapshot) {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = snapshot.canPlay
        center.pauseCommand.isEnabled = snapshot.canPause
        center.togglePlayPauseCommand.isEnabled = snapshot.canPlay || snapshot.canPause
        center.nextTrackCommand.isEnabled = snapshot.canNext
        center.previousTrackCommand.isEnabled = snapshot.canPrevious
        center.changePlaybackPositionCommand.isEnabled = snapshot.canSeek
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
        center.changePlaybackPositionCommand.addTarget { [commandRelay] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            commandRelay.send(.seek(event.positionTime))
            return .success
        }
    }

    private func handle(_ command: RemoteCommand) {
        Task {
            await perform(command, on: player)
        }
    }
}
#endif
