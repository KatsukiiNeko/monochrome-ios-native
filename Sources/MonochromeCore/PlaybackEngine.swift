// PlaybackEngine.swift: what the player needs from an audio backend.
import Foundation

public enum PlaybackEvent: Equatable, Sendable {
    /// Emitted once the item is ready; `format` is what the decoder parsed.
    case ready(duration: Double?, format: AudioFormat?)
    case position(Double)
    case finished
    case failed(String)

    /// Short name for a log line.
    public var kind: String {
        switch self {
        case .ready: "ready"
        case .position: "position"
        case .finished: "finished"
        case .failed: "failed"
        }
    }
}

/// An engine event wearing the token of the attempt that produced it. The
/// controller ignores events whose token is no longer the newest attempt.
public struct PlaybackEngineEvent: Equatable, Sendable {
    public let token: PlaybackToken
    public let event: PlaybackEvent

    public init(token: PlaybackToken, event: PlaybackEvent) {
        self.token = token
        self.event = event
    }
}

/// Implemented by the iOS layer with AVPlayer; faked in tests.
@MainActor
public protocol PlaybackEngine: AnyObject {
    var onEvent: ((PlaybackEngineEvent) -> Void)? { get set }
    /// `contentType` is the out-of-band MIME type when the server does not state
    /// a usable one; nil lets AVFoundation decide. `headers` are applied only
    /// when the backend supports them; unsupported headers are ignored (recorded
    /// as a limitation rather than worked around). `token` identifies the
    /// attempt: a load older than the newest accepted load must not replace the
    /// item and must throw `PlaybackSuperseded`.
    func load(url: URL, contentType: String?, headers: [String: String], token: PlaybackToken) async throws
    func play()
    func pause()
    func seek(to seconds: Double)
    func stop()
    /// Pauses and detaches the current item without invalidating the load arbiter.
    /// Called when a new attempt starts so the previous song never plays under a
    /// new title.
    func halt()
    /// What the engine is actually doing; the controller derives UI state from it.
    var facts: EngineFacts { get }
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
    func halt() {}
    /// Backends that do not report facts are treated as healthy, so the stall
    /// policy never reloads them.
    var facts: EngineFacts { .optimistic }
}
