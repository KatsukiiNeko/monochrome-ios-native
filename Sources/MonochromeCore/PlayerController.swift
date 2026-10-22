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
    /// Repeat control; `one` restarts the current track at its end.
    public private(set) var repeatMode: RepeatMode = .off
    /// True when the engine is playing a file served from the audio cache.
    public private(set) var isCurrentFromCache = false

    /// Called once per successful start; the app uses it to record history.
    public var onTrackStarted: ((Track) -> Void)?
    /// Technical log sink; the app forwards these to os.Logger.
    public var log: ((String) -> Void)?

    private let engine: any PlaybackEngine
    private let resolver: any TrackURLResolver
    private let cache: (any AudioCaching)?
    /// One fresh resolution per track after a failure, then the error is shown.
    private var didRetryCurrentTrack = false
    /// True while the engine holds a file, so a restart needs no network round trip.
    private var currentItemIsLocal = false
    /// Stream resolved for the current item, waiting for the parsed format before caching.
    private var pendingCache: PendingCache?

    private struct PendingCache {
        var track: Track
        var quality: AudioQuality?
        var url: URL
        var contentType: String?
    }

    public var currentTrack: Track? { queue.current }
    public var isPlaying: Bool { state == .playing }

    public init(
        engine: any PlaybackEngine,
        resolver: any TrackURLResolver,
        cache: (any AudioCaching)? = nil
    ) {
        self.engine = engine
        self.resolver = resolver
        self.cache = cache
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
            isCurrentFromCache = false
            currentItemIsLocal = false
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

    public func setRepeatMode(_ mode: RepeatMode) {
        repeatMode = mode
    }

    public func cycleRepeatMode() {
        repeatMode = repeatMode.next
    }

    // MARK: - Engine events

    func handle(_ event: PlaybackEvent) async {
        switch event {
        case .ready(let engineDuration, let engineFormat):
            if let engineFormat { format = engineFormat }
            if let engineDuration, engineDuration > 0 {
                duration = engineDuration
            }
            startCacheStoreIfReady(format: engineFormat, duration: engineDuration ?? duration)
        case .position(let seconds):
            position = seconds
        case .finished:
            await handleEndOfTrack()
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

    private func startCacheStoreIfReady(format: AudioFormat?, duration: Double) {
        guard let cache, let pending = pendingCache else { return }
        pendingCache = nil
        Task(priority: .utility) {
            await cache.store(
                pending.track,
                quality: pending.quality,
                url: pending.url,
                contentType: pending.contentType,
                format: format,
                duration: duration
            )
        }
    }

    private func handleEndOfTrack() async {
        let hasNext = queue.currentIndex.map { $0 + 1 < queue.tracks.count } ?? false
        let action = EndOfTrackDecision.action(
            repeatMode: repeatMode,
            hasNext: hasNext,
            hasTracks: !queue.isEmpty,
            itemIsLocal: currentItemIsLocal
        )
        switch action {
        case .advance:
            await next()
        case .wrap:
            guard queue.jump(to: 0) != nil else { return }
            await loadCurrent()
        case .replayInPlace:
            log?(isCurrentFromCache ? "loop source=cache" : "loop source=local-file")
            engine.seek(to: 0)
            position = 0
            engine.play()
            state = .playing
        case .reload:
            await loadCurrent(forLoop: true)
        case .stop:
            engine.stop()
            position = 0
            state = .idle
            isCurrentFromCache = false
            currentItemIsLocal = false
        }
    }

    private func loadCurrent(retrying: Bool = false, forLoop: Bool = false) async {
        guard let track = queue.current else {
            engine.stop()
            state = .idle
            position = 0
            duration = 0
            currentItemIsLocal = false
            isCurrentFromCache = false
            pendingCache = nil
            return
        }
        if !retrying { didRetryCurrentTrack = false }

        state = .loading
        format = nil
        position = 0
        duration = track.durationSeconds ?? 0
        isCurrentFromCache = false
        pendingCache = nil

        if track.isStreaming, let cache,
           let cached = await cache.cachedAudio(for: track, quality: track.audioQuality) {
            do {
                try await engine.load(url: cached.url, contentType: nil)
                engine.play()
                state = .playing
                format = cached.format
                if let cachedDuration = cached.duration, cachedDuration > 0 {
                    duration = cachedDuration
                }
                currentItemIsLocal = true
                isCurrentFromCache = true
                if forLoop { log?("loop source=cache") }
                onTrackStarted?(track)
                return
            } catch {
                // A damaged cache entry must not stop playback; resolve the stream instead.
                log?("cache hit unusable track=\(track.id)")
            }
        }
        if forLoop { log?("loop source=network reason=cache-miss") }

        do {
            let url = try await resolver.url(for: track)
            let contentType = await resolver.contentType(for: track)
            pendingCache = PendingCache(
                track: track,
                quality: track.audioQuality,
                url: url,
                contentType: contentType
            )
            try await engine.load(url: url, contentType: contentType)
            engine.play()
            state = .playing
            currentItemIsLocal = !track.isStreaming
            onTrackStarted?(track)
        } catch {
            pendingCache = nil
            if !retrying, track.isStreaming, !didRetryCurrentTrack {
                didRetryCurrentTrack = true
                await loadCurrent(retrying: true, forLoop: forLoop)
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }
}
