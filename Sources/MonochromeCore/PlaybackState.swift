// PlaybackState.swift: the states the player UI switches on.
import Foundation

public enum PlaybackState: Equatable, Sendable {
    case idle
    case loading
    case playing
    case paused
    case failed(String)
}
