// PlaybackEngine.swift: what the player needs from an audio backend.
import Foundation

public enum PlaybackEvent: Equatable, Sendable {
    case ready(duration: Double?)
    case position(Double)
    case finished
    case failed(String)
}

/// Implemented by the iOS layer with AVPlayer; faked in tests.
@MainActor
public protocol PlaybackEngine: AnyObject {
    var onEvent: ((PlaybackEvent) -> Void)? { get set }
    /// `contentType` is the out-of-band MIME type when the server does not state
    /// a usable one; nil lets AVFoundation decide.
    func load(url: URL, contentType: String?) async throws
    func play()
    func pause()
    func seek(to seconds: Double)
    func stop()
}
