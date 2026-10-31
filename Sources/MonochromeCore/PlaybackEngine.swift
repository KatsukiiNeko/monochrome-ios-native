// PlaybackEngine.swift: what the player needs from an audio backend.
import Foundation

public enum PlaybackEvent: Equatable, Sendable {
    /// Emitted once the item is ready; `format` is what the decoder parsed.
    case ready(duration: Double?, format: AudioFormat?)
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
    /// Applies the equalizer to items this engine can process. Backends that
    /// cannot process audio ignore it.
    func setEqualizer(_ settings: EQSettings)
    /// Whether the current item can carry the equalizer.
    var eqAvailability: EQAvailability { get }
    /// Largest pre-limiter sample seen since the last call, for the clip light.
    func takeEqualizerPeak() -> Double
}

public extension PlaybackEngine {
    func setEqualizer(_ settings: EQSettings) {}
    var eqAvailability: EQAvailability { .available }
    func takeEqualizerPeak() -> Double { 0 }
}
