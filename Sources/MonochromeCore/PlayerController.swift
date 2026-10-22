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

    private let engine: any PlaybackEngine
    private let urlForTrack: (Track) -> URL?

    public var currentTrack: Track? { queue.current }
    public var isPlaying: Bool { state == .playing }

    public init(engine: any PlaybackEngine, urlForTrack: @escaping (Track) -> URL?) {
        self.engine = engine
        self.urlForTrack = urlForTrack
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
            if queue.current != nil {
                await loadCurrent()
            }
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

    // MARK: - Engine events

    func handle(_ event: PlaybackEvent) async {
        switch event {
        case .ready(let engineDuration):
            if let engineDuration, engineDuration > 0 {
                duration = engineDuration
            }
        case .position(let seconds):
            position = seconds
        case .finished:
            await next()
        case .failed(let message):
            state = .failed(message)
        }
    }

    // MARK: - Internals

    private func loadCurrent() async {
        guard let track = queue.current else {
            engine.stop()
            state = .idle
            position = 0
            duration = 0
            return
        }
        guard let url = urlForTrack(track) else {
            state = .failed("The audio file for “\(track.title)” is missing.")
            return
        }

        state = .loading
        position = 0
        duration = track.durationSeconds ?? 0
        do {
            try await engine.load(url: url)
            engine.play()
            state = .playing
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
