// PlaybackOwnership.swift: numbers every attempt to start a track.
import Foundation

/// Identifies one attempt to start a track. A newer attempt always has a larger value.
public struct PlaybackToken: Hashable, Sendable, Comparable {
    public let value: UInt64

    public init(value: UInt64) {
        self.value = value
    }

    public static func < (lhs: PlaybackToken, rhs: PlaybackToken) -> Bool {
        lhs.value < rhs.value
    }
}

/// Hands out tokens and answers one question: is this token still the newest?
public struct PlaybackOwnership: Sendable {
    private var latest: UInt64 = 0

    public init() {}

    /// Call at the start of every attempt: play, next, previous, retry, restore.
    public mutating func begin() -> PlaybackToken {
        latest &+= 1
        return PlaybackToken(value: latest)
    }

    /// Call on stop or queue clear: every older token dies at once.
    public mutating func invalidateAll() {
        latest &+= 1
    }

    public func owns(_ token: PlaybackToken) -> Bool {
        token.value == latest
    }
}

/// The decision an engine makes before touching the player: a load older than the
/// newest accepted load must not replace the item. Shared by the AVFoundation
/// engine and the host tests so both exercise the same rule.
public struct PlaybackLoadArbiter: Sendable {
    private var newest: UInt64 = 0

    public init() {}

    /// Records an incoming load. Returns false when a newer load already started.
    public mutating func accept(_ token: PlaybackToken) -> Bool {
        guard token.value >= newest else { return false }
        newest = token.value
        return true
    }

    /// True while `token` is still the newest accepted load.
    public func owns(_ token: PlaybackToken) -> Bool {
        token.value == newest
    }
}

/// Not a failure: a newer attempt owns playback, so this one must say nothing.
public struct PlaybackSuperseded: Error, Equatable, Sendable {
    public init() {}
}
