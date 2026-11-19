// PlaybackState.swift: the states the player UI switches on.
import Foundation

/// Why playback stopped. Only this reason may clear system metadata.
public enum StopReason: String, Sendable, Equatable {
    case queueCleared
    case endOfQueue
}

public enum PlaybackState: Equatable, Sendable {
    case idle
    case loading(autoPlay: Bool)
    case playing
    case paused
    case failed(String)
    /// Playback ended on purpose: the only state that may clear Now Playing.
    case stopped(StopReason)

    /// Short name for a log line.
    public var logName: String {
        switch self {
        case .idle: "idle"
        case .loading(let autoPlay): "loading(autoPlay:\(autoPlay))"
        case .playing: "playing"
        case .paused: "paused"
        case .failed: "failed"
        case .stopped(let reason): "stopped(\(reason.rawValue))"
        }
    }
}
