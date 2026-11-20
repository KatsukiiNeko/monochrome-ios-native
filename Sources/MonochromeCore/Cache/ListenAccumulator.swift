// ListenAccumulator.swift: how much of a track was actually heard.
import Foundation

/// Counts time actually listened to. A seek or a pause is not listening, so the
/// value only grows while the engine is playing and the playhead moves forward
/// at a plausible speed.
public struct ListenAccumulator: Sendable {
    public private(set) var seconds: TimeInterval = 0
    private var last: TimeInterval?

    public init() {}

    public mutating func tick(position: TimeInterval, isPlaying: Bool) {
        defer { last = position }
        guard isPlaying, let last else { return }
        let delta = position - last
        // Ticks arrive once a second; a larger jump is a seek, not listening.
        if delta > 0 && delta <= 2.5 {
            seconds += delta
        }
    }

    public mutating func reset() {
        seconds = 0
        last = nil
    }

    public func fraction(of duration: TimeInterval) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, seconds / duration)
    }
}

public enum StreamStorageDecision: Equatable, Sendable {
    case keepBuffering
    case completeAndPromote
}

public enum StreamStoragePolicy {
    /// Half the track heard is the point where it is worth keeping. A skipped
    /// song never gets there, so its download is cancelled instead.
    public static let promotionFraction = 0.5

    public static func decide(
        listened: ListenAccumulator,
        duration: TimeInterval?
    ) -> StreamStorageDecision {
        guard let duration, duration > 0 else { return .keepBuffering }
        return listened.fraction(of: duration) >= promotionFraction ? .completeAndPromote : .keepBuffering
    }
}
