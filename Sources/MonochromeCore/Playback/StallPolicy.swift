// StallPolicy.swift: what the engine is actually doing, and how to recover.
import Foundation

/// What AVFoundation (or another backend) reports right now. Intent lives in
/// `PlaybackState`; these are facts, and the UI must show them.
public enum ItemStatus: Equatable, Sendable {
    case unknown
    case ready
    case failed

    public var logName: String {
        switch self {
        case .unknown: "unknown"
        case .ready: "ready"
        case .failed: "failed"
        }
    }
}

public enum TimeControl: Equatable, Sendable {
    case paused
    case waiting
    case playing
}

public struct EngineFacts: Equatable, Sendable {
    public var itemStatus: ItemStatus
    public var timeControl: TimeControl
    public var likelyToKeepUp: Bool
    public var bufferEmpty: Bool

    public init(
        itemStatus: ItemStatus,
        timeControl: TimeControl,
        likelyToKeepUp: Bool,
        bufferEmpty: Bool
    ) {
        self.itemStatus = itemStatus
        self.timeControl = timeControl
        self.likelyToKeepUp = likelyToKeepUp
        self.bufferEmpty = bufferEmpty
    }

    /// A backend that cannot report facts still answers honestly-enough for the
    /// policy to leave it alone.
    public static let optimistic = EngineFacts(
        itemStatus: .unknown,
        timeControl: .playing,
        likelyToKeepUp: true,
        bufferEmpty: false
    )

    /// True only when the engine is really producing audio.
    public var isProducingAudio: Bool { itemStatus != .failed && timeControl == .playing }
}

public enum RecoveryAction: Equatable, Sendable {
    case none
    case showBuffering
    case retryPlay
    case reloadFromPosition
    case fail
}

public enum StallPolicy {
    public static let reloadLimit = 2

    /// `stalledFor` is how long the facts have disagreed with the listener's
    /// intent. A reload is a fresh attempt that seeks back to the saved position.
    public static func decide(
        wantsToPlay: Bool,
        facts: EngineFacts,
        stalledFor: TimeInterval,
        reloads: Int
    ) -> RecoveryAction {
        guard wantsToPlay else { return .none }
        if facts.itemStatus == .failed { return reloads < reloadLimit ? .reloadFromPosition : .fail }
        switch facts.timeControl {
        case .playing:
            return .none
        case .waiting:
            if stalledFor > 8 { return reloads < reloadLimit ? .reloadFromPosition : .fail }
            return .showBuffering
        case .paused:
            if stalledFor > 3 { return reloads < reloadLimit ? .reloadFromPosition : .fail }
            if stalledFor > 1.5 { return .retryPlay }
            return .none
        }
    }
}
