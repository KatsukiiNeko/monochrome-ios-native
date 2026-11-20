// NowPlayingPlan.swift: what the system now-playing surface should show, as data.
import Foundation

/// The identity of the track the system should display.
public struct NowPlayingIdentity: Equatable, Sendable {
    public var trackID: String
    public var title: String
    public var artist: String
    public var album: String?
    public var duration: TimeInterval?

    public init(trackID: String, title: String, artist: String, album: String?, duration: TimeInterval?) {
        self.trackID = trackID
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
    }
}

/// The user-facing state the system surface describes. `identity == nil` with no
/// stop reason means "no track right now", which is transient and never clears.
public struct NowPlayingState: Equatable, Sendable {
    public var identity: NowPlayingIdentity?
    /// The listener's intent: stays true while a requested track buffers.
    public var isPlaying: Bool
    /// Set only by an explicit stop.
    public var stopReason: StopReason?
    public var artworkReady: Bool

    public init(
        identity: NowPlayingIdentity?,
        isPlaying: Bool,
        stopReason: StopReason?,
        artworkReady: Bool
    ) {
        self.identity = identity
        self.isPlaying = isPlaying
        self.stopReason = stopReason
        self.artworkReady = artworkReady
    }
}

public enum NowPlayingAction: Equatable, Sendable {
    /// Full dictionary: text, duration, rate and elapsed time.
    case publishIdentity
    /// Rate and elapsed time only.
    case updatePlaybackState
    case attachArtwork
    case clear(StopReason)
}

public enum NowPlayingPlanner {
    /// `old` is the state last published (nil if nothing was ever published).
    public static func actions(from old: NowPlayingState?, to new: NowPlayingState) -> [NowPlayingAction] {
        // Only an explicit stop clears, and only once.
        if let reason = new.stopReason {
            return old?.identity == nil ? [] : [.clear(reason)]
        }
        // A missing track without a stop is transient: hold what is on screen.
        guard let identity = new.identity else { return [] }

        var actions: [NowPlayingAction] = []
        if old?.identity != identity {
            // The track changed, or its duration arrived: publish immediately.
            actions.append(.publishIdentity)
        } else if old?.isPlaying != new.isPlaying {
            // Play or pause: update the two time-related keys immediately.
            actions.append(.updatePlaybackState)
        }
        let artworkAlreadyShown = old?.artworkReady == true && old?.identity?.trackID == identity.trackID
        if new.artworkReady && !artworkAlreadyShown {
            actions.append(.attachArtwork)
        }
        return actions
    }
}

public enum NowPlayingProjection {
    /// Maps player state to what the system should show. Pure, so the rules are
    /// testable without MediaPlayer.
    public static func make(
        phase: PlaybackState,
        track: Track?,
        duration: TimeInterval?,
        artworkReady: Bool,
        enginePlaying: Bool = true
    ) -> NowPlayingState {
        let knownDuration = duration.flatMap { $0 > 0 ? $0 : nil }
        switch phase {
        case .stopped(let reason):
            return NowPlayingState(identity: nil, isPlaying: false, stopReason: reason, artworkReady: false)
        case .idle:
            return NowPlayingState(identity: nil, isPlaying: false, stopReason: nil, artworkReady: false)
        case .loading(let autoPlay):
            // A buffering track keeps its identity but the system rate is 0, so
            // iOS never advances the Lock Screen progress bar over silence.
            return state(track, knownDuration, isPlaying: autoPlay && enginePlaying, artworkReady)
        case .playing:
            return state(track, knownDuration, isPlaying: enginePlaying, artworkReady)
        case .paused, .failed:
            return state(track, knownDuration, isPlaying: false, artworkReady)
        }
    }

    private static func state(
        _ track: Track?,
        _ duration: TimeInterval?,
        isPlaying: Bool,
        _ artworkReady: Bool
    ) -> NowPlayingState {
        guard let track else {
            // Transient: the planner holds what is already on screen.
            return NowPlayingState(identity: nil, isPlaying: isPlaying, stopReason: nil, artworkReady: false)
        }
        let identity = NowPlayingIdentity(
            trackID: track.id,
            title: track.title,
            artist: track.displayArtist,
            album: track.album.isEmpty ? nil : track.album,
            duration: duration
        )
        return NowPlayingState(
            identity: identity,
            isPlaying: isPlaying,
            stopReason: nil,
            artworkReady: artworkReady
        )
    }
}
