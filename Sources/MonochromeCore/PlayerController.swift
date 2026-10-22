// PlayerController.swift: owns playback state, the queue and the engine; views only read it.
import Foundation
import Observation

@MainActor
@Observable
public final class PlayerController {
    public private(set) var state: PlaybackState = .idle
    public private(set) var queue = Queue()
    public private(set) var position: Double = 0
    public private(set) var duration: Double = 0
    /// Parsed format of the current stream; nil until the item is ready.
    public private(set) var format: AudioFormat?

    /// Called once per successful start; the app uses it to record history.
    public var onTrackStarted: ((Track) -> Void)?

    private let engine: any PlaybackEngine
    private let resolver: any TrackURLResolver
    /// One fresh resolution per track after a failure, then the error is shown.
    private var didRetryCurrentTrack = false

    public var currentTrack: Track? { queue.current }
    public var isPlaying: Bool { state == .playing }

    public init(engine: any PlaybackEngine, resolver: any TrackURLResolver) {
        self.engine = engine
        self.resolver = resolver
        engine.onEvent = { [weak self] event in
            guard let self else { return }
            Task { await self.handle(event) }
        }
    }

    // MARK: - Commands

    public func play(tracks: [Track], startingAt index: Int) async {
        queue.replace(with: tracks, startingAt: index)
        await loadCurrent()
    }

    public func togglePlayPause() async {
        switch state {
        case .playing:
            engine.pause()
            state = .paused
        case .paused:
            engine.play()
            state = .playing
        case .idle, .failed:
            await retry()
        case .loading:
            break
        }
    }

    public func next() async {
        if queue.advance() != nil {
            await loadCurrent()
        } else {
            engine.stop()
            position = 0
            state = .idle
        }
    }

    /// Restarts the current track first unless it just started, like most players.
    public func previous() async {
        if position > 3 {
            engine.seek(to: 0)
            position = 0
        } else if queue.rewind() != nil {
            await loadCurrent()
        } else {
            engine.seek(to: 0)
            position = 0
        }
    }

    public func seek(to seconds: Double) {
        guard queue.current != nil else { return }
        let clamped = max(0, duration > 0 ? min(seconds, duration) : seconds)
        position = clamped
        engine.seek(to: clamped)
    }

    public func jump(to index: Int) async {
        guard queue.jump(to: index) != nil else { return }
        await loadCurrent()
    }

    public func append(_ tracks: [Track]) {
        queue.append(tracks)
    }

    public func removeTrack(at index: Int) async {
        let removedCurrent = queue.current?.id
        guard let removed = queue.remove(at: index) else { return }
        if removed.id == removedCurrent {
            await loadCurrent()
        }
    }

    public func moveQueue(from source: Int, to destination: Int) {
        queue.move(from: source, to: destination)
    }

    /// User-initiated retry, including a fresh stream resolution.
    public func retry() async {
        guard queue.current != nil else { return }
        didRetryCurrentTrack = false
        await loadCurrent()
    }

    // MARK: - Engine events

    func handle(_ event: PlaybackEvent) async {
        switch event {
        case .ready(let engineDuration, let engineFormat):
            format = engineFormat
            if let engineDuration, engineDuration > 0 {
                duration = engineDuration
            }
        case .position(let seconds):
            position = seconds
        case .finished:
            await next()
        case .failed(let message):
            // A stream can expire mid-playback; resolve once more before giving up.
            if queue.current?.isStreaming == true, !didRetryCurrentTrack {
                didRetryCurrentTrack = true
                await loadCurrent(retrying: true)
            } else {
                state = .failed(message)
            }
        }
    }

    // MARK: - Internals

    private func loadCurrent(retrying: Bool = false) async {
        guard let track = queue.current else {
            engine.stop()
            state = .idle
            position = 0
            duration = 0
            return
        }
        if !retrying { didRetryCurrentTrack = false }

        state = .loading
        format = nil
        position = 0
        duration = track.durationSeconds ?? 0
        do {
            let url = try await resolver.url(for: track)
            let contentType = await resolver.contentType(for: track)
            try await engine.load(url: url, contentType: contentType)
            engine.play()
            state = .playing
            onTrackStarted?(track)
        } catch {
            if !retrying, track.isStreaming, !didRetryCurrentTrack {
                didRetryCurrentTrack = true
                await loadCurrent(retrying: true)
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }
}
