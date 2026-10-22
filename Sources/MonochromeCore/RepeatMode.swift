// RepeatMode.swift: repeat modes and the pure end-of-track decision.
import Foundation

/// Repeat control state; `one` is the loop option that may replay from the cache.
public enum RepeatMode: String, Codable, Sendable, CaseIterable, Equatable {
    case off
    case all
    case one

    /// The mode shown after tapping the control once more.
    public var next: RepeatMode {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }

    public var label: String {
        switch self {
        case .off: "Repeat off"
        case .all: "Repeat all"
        case .one: "Repeat one"
        }
    }

    /// SF Symbol name; `repeat.1` carries the numeral for the loop option.
    public var symbolName: String {
        switch self {
        case .off, .all: "repeat"
        case .one: "repeat.1"
        }
    }
}

/// What the player should do when the current item reaches its end.
public enum EndOfTrackAction: Equatable, Sendable {
    /// Move to the next queued track.
    case advance
    /// Jump back to the first queued track.
    case wrap
    /// The current item is a local file: seeking to zero restarts it without I/O.
    case replayInPlace
    /// Reload the current track, which resolves it again.
    case reload
    case stop
}

public enum EndOfTrackDecision {
    public static func action(
        repeatMode: RepeatMode,
        hasNext: Bool,
        hasTracks: Bool,
        itemIsLocal: Bool
    ) -> EndOfTrackAction {
        switch repeatMode {
        case .one:
            return itemIsLocal ? .replayInPlace : .reload
        case .off, .all:
            if hasNext { return .advance }
            if repeatMode == .all, hasTracks { return .wrap }
            return .stop
        }
    }
}
