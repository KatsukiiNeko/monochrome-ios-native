// NowPlayingSnapshot.swift: presentation values for the system now-playing surface.
import Foundation

/// Playback states the now-playing surface understands.
public enum NowPlayingPlaybackState: Equatable, Sendable {
    case stopped
    case paused
    case playing
}

/// Immutable view of the player, derived from `PlayerController` and owned by nobody.
public struct NowPlayingSnapshot: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var duration: Double
    public var elapsed: Double
    /// 1.0 while playing, 0.0 otherwise.
    public var rate: Double
    public var canPlay: Bool
    public var canPause: Bool
    public var canNext: Bool
    public var canPrevious: Bool
    public var canSeek: Bool
    public var playbackState: NowPlayingPlaybackState

    public init(
        title: String,
        artist: String,
        album: String,
        duration: Double,
        elapsed: Double,
        rate: Double,
        canPlay: Bool,
        canPause: Bool,
        canNext: Bool,
        canPrevious: Bool,
        canSeek: Bool,
        playbackState: NowPlayingPlaybackState
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.elapsed = elapsed
        self.rate = rate
        self.canPlay = canPlay
        self.canPause = canPause
        self.canNext = canNext
        self.canPrevious = canPrevious
        self.canSeek = canSeek
        self.playbackState = playbackState
    }

    /// Maps the player's real state to what the OS should show and enable.
    public static func make(
        track: Track?,
        state: PlaybackState,
        position: Double,
        duration: Double,
        hasNext: Bool,
        hasPrevious: Bool
    ) -> NowPlayingSnapshot {
        guard let track else {
            return NowPlayingSnapshot(
                title: "",
                artist: "",
                album: "",
                duration: 0,
                elapsed: 0,
                rate: 0,
                canPlay: false,
                canPause: false,
                canNext: false,
                canPrevious: false,
                canSeek: false,
                playbackState: .stopped
            )
        }

        let playbackState: NowPlayingPlaybackState
        let canPlay: Bool
        let canPause: Bool
        let canSeek: Bool
        switch state {
        case .playing:
            playbackState = .playing
            canPlay = false
            canPause = true
            canSeek = duration > 0
        case .paused:
            playbackState = .paused
            canPlay = true
            canPause = false
            canSeek = duration > 0
        case .loading:
            // Not ready yet: no transport action would succeed.
            playbackState = .paused
            canPlay = false
            canPause = false
            canSeek = false
        case .idle:
            playbackState = .stopped
            canPlay = true
            canPause = false
            canSeek = duration > 0
        case .failed:
            // Play retries the failed item.
            playbackState = .stopped
            canPlay = true
            canPause = false
            canSeek = false
        }

        return NowPlayingSnapshot(
            title: track.title,
            artist: track.displayArtist,
            album: track.album,
            duration: duration,
            elapsed: position,
            rate: playbackState == .playing ? 1.0 : 0.0,
            canPlay: canPlay,
            canPause: canPause,
            canNext: hasNext,
            canPrevious: hasPrevious,
            canSeek: canSeek,
            playbackState: playbackState
        )
    }
}

/// Commands the system can send back to the player.
public enum RemoteCommand: Equatable, Sendable {
    case play
    case pause
    case toggle
    case next
    case previous
    case seek(Double)
}

@MainActor
public protocol RemoteCommandTarget: AnyObject {
    var isPlaying: Bool { get }
    func togglePlayPause() async
    func next() async
    func previous() async
    func seek(to seconds: Double)
}

/// Routes a remote command, skipping play/pause when the player is already in that state.
@MainActor
public func perform(_ command: RemoteCommand, on target: any RemoteCommandTarget) async {
    switch command {
    case .play:
        if !target.isPlaying { await target.togglePlayPause() }
    case .pause:
        if target.isPlaying { await target.togglePlayPause() }
    case .toggle:
        await target.togglePlayPause()
    case .next:
        await target.next()
    case .previous:
        await target.previous()
    case .seek(let seconds):
        target.seek(to: seconds)
    }
}
