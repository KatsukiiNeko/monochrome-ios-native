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
    /// Measured output-route latency; synced lyrics shift by it so the text
    /// matches what is heard, not the player clock.
    public private(set) var outputLatency: TimeInterval = 0
    /// True when the engine is playing a file served from the audio cache.
    public private(set) var isCurrentFromCache = false
    /// True when the engine is playing a permanent download.
    public private(set) var isCurrentFromDownload = false
    /// When the sleep timer will pause playback; nil when no timer is armed.
    public private(set) var sleepTimerEnd: Date?

    /// Called once per successful start; the app uses it to record history.
    public var onTrackStarted: ((Track) -> Void)?
    /// Technical log sink; the app forwards these to os.Logger.
    public var log: ((String) -> Void)?

    private let engine: any PlaybackEngine
    private let resolver: any TrackURLResolver
    private let cache: (any AudioCaching)?
    private let downloads: (any DownloadedAudioProviding)?
    private let now: @Sendable () -> Date
    /// A download may be cancelled only while the track has just started.
    private static let skipCancellationWindow: TimeInterval = 10
    /// One fresh resolution per track after a failure, then the error is shown.
    private var didRetryCurrentTrack = false
    /// True while the engine holds a file, so a restart needs no network round trip.
    private var currentItemIsLocal = false
    /// Stream resolved for the current item, waiting for the parsed format before caching.
    private var pendingCache: PendingCache?
    /// When the current item started, used to decide whether skipping should cancel its cache.
    private var playbackStartedAt: Date?
    /// The track whose background download belongs to the current item.
    private var cacheDownloadTrack: Track?
    private var sleepTimerTask: Task<Void, Never>?

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
        cache: (any AudioCaching)? = nil,
        downloads: (any DownloadedAudioProviding)? = nil,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.engine = engine
        self.resolver = resolver
        self.cache = cache
        self.downloads = downloads
        self.now = now
        engine.onEvent = { [weak self] event in
            guard let self else { return }
            if case .ready(let duration, let format) = event {
                // Handle ready on the spot: a deferred handler can consume the next
                // track's pending cache after a quick skip.
                MainActor.assumeIsolated {
                    self.handleReady(duration: duration, format: format)
                }
            } else {
                Task { await self.handle(event) }
            }
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
            await cancelCacheDownloadIfSkippedEarly()
            playbackStartedAt = nil
            cacheDownloadTrack = nil
            engine.stop()
            position = 0
            state = .idle
            isCurrentFromCache = false
            isCurrentFromDownload = false
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

    /// Bluetooth and AirPlay routes buffer audio, so the heard sound lags the
    /// player clock. Clamped to 0.5 s: a longer route would be unusable for video.
    public func setOutputLatency(_ seconds: TimeInterval) {
        outputLatency = min(max(seconds, 0), 0.5)
    }

    public func cycleRepeatMode() {
        repeatMode = repeatMode.next
    }

    /// Arms a one-shot timer that pauses playback; setting a new one replaces the old.
    public func startSleepTimer(seconds: TimeInterval) {
        cancelSleepTimer()
        guard seconds > 0 else { return }
        let deadline = now().addingTimeInterval(seconds)
        sleepTimerEnd = deadline
        log?("sleep timer armed seconds=\(Int(seconds.rounded()))")
        sleepTimerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.fireSleepTimer(deadline: deadline)
        }
    }

    public func cancelSleepTimer() {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        guard sleepTimerEnd != nil else { return }
        sleepTimerEnd = nil
        log?("sleep timer cancelled")
    }

    /// A replaced or cancelled timer leaves its task behind; the deadline rejects it.
    private func fireSleepTimer(deadline: Date) {
        guard sleepTimerEnd == deadline else { return }
        sleepTimerEnd = nil
        sleepTimerTask = nil
        guard isPlaying else {
            log?("sleep timer expired state=\(state)")
            return
        }
        engine.pause()
        state = .paused
        log?("sleep timer fired")
    }

    // MARK: - Engine events

    func handle(_ event: PlaybackEvent) async {
        switch event {
        case .ready(let engineDuration, let engineFormat):
            handleReady(duration: engineDuration, format: engineFormat)
        case .position(let seconds):
            position = seconds
        case .finished:
            await handleEndOfTrack()
        case .failed(let message):
            log?("playback failure message=\(message)")
            // A load failure is thrown by `load` and handled where it was awaited.
            // A relayed copy during `.loading` is that same failed item; letting it
            // through here would replace the staged retry with a visible failure.
            if case .loading = state {
                log?("playback failure ignored reason=loading")
                return
            }
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

    private func handleReady(duration engineDuration: Double?, format engineFormat: AudioFormat?) {
        format = mergedFormat(stored: format, measured: engineFormat)
        if let engineDuration, engineDuration > 0 {
            duration = engineDuration
        }
        startCacheStoreIfReady(format: format, duration: engineDuration ?? duration)
    }

    /// Measured fields win over values stored with a cached or downloaded file; a
    /// disagreement is logged by field name so an unexpected conversion is visible.
    private func mergedFormat(stored: AudioFormat?, measured: AudioFormat?) -> AudioFormat? {
        guard var stored else { return measured }
        guard let measured else { return stored }

        func pick<T: Equatable>(_ old: T?, _ new: T?, _ name: String) -> T? {
            guard let new else { return old }
            if let old, old != new {
                log?("audiospec mismatch field=\(name)")
            }
            return new
        }

        if !measured.codec.isEmpty {
            if stored.codec != measured.codec, !stored.codec.isEmpty {
                log?("audiospec mismatch field=codec")
            }
            stored.codec = measured.codec
        }
        stored.sampleRateHz = pick(stored.sampleRateHz, measured.sampleRateHz, "sampleRate")
        stored.bitDepth = pick(stored.bitDepth, measured.bitDepth, "bitDepth")
        stored.channels = pick(stored.channels, measured.channels, "channels")
        stored.bitrateKbps = pick(stored.bitrateKbps, measured.bitrateKbps, "bitrate")
        if measured.bitrateKbps != nil {
            stored.bitrateIsEstimated = measured.bitrateIsEstimated
        }
        return stored
    }

    private func startCacheStoreIfReady(format: AudioFormat?, duration: Double) {
        guard let cache, let pending = pendingCache else { return }
        pendingCache = nil
        guard pending.track.id == queue.current?.id else {
            log?("cache skip track=\(pending.track.id) reason=stale")
            return
        }
        cacheDownloadTrack = pending.track
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

    /// Skips cancel the download only while the track is still starting; later skips
    /// let it finish so a track played for a while still becomes a cache hit.
    private func cancelCacheDownloadIfSkippedEarly() async {
        guard let cache, let track = cacheDownloadTrack else { return }
        // Retrying or looping the same track is not a skip.
        if queue.current?.id == track.id { return }
        let started = playbackStartedAt ?? now()
        let elapsed = now().timeIntervalSince(started)
        cacheDownloadTrack = nil
        guard elapsed < Self.skipCancellationWindow else { return }
        log?("cache cancel track=\(track.id) reason=skipped elapsed=\(Int(elapsed))")
        await cache.cancelDownload(for: track, quality: track.audioQuality, reason: "skipped")
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
            isCurrentFromDownload = false
            currentItemIsLocal = false
        }
    }

    private func loadCurrent(retrying: Bool = false, forLoop: Bool = false) async {
        await cancelCacheDownloadIfSkippedEarly()
        if let cache { await cache.clearProtection() }
        playbackStartedAt = nil
        guard let track = queue.current else {
            engine.stop()
            state = .idle
            position = 0
            duration = 0
            currentItemIsLocal = false
            isCurrentFromCache = false
            isCurrentFromDownload = false
            pendingCache = nil
            return
        }
        if !retrying { didRetryCurrentTrack = false }

        state = .loading
        format = nil
        position = 0
        duration = track.durationSeconds ?? 0
        isCurrentFromCache = false
        isCurrentFromDownload = false
        pendingCache = nil

        if track.isStreaming, let downloads,
           let downloaded = await downloads.downloadedFile(for: track) {
            do {
                log?("play start id=\(track.id) source=\(track.source.rawValue) via=download \(urlSummary(downloaded.url))")
                try await engine.load(url: downloaded.url, contentType: nil)
                engine.play()
                state = .playing
                format = mergedFormat(stored: downloaded.format, measured: format)
                if let downloadedDuration = downloaded.duration, downloadedDuration > 0 {
                    duration = downloadedDuration
                }
                currentItemIsLocal = true
                isCurrentFromDownload = true
                playbackStartedAt = now()
                if forLoop { log?("loop source=download") }
                log?("download source=file track=\(track.id)")
                onTrackStarted?(track)
                return
            } catch {
                log?("download unusable track=\(track.id) error=\(describe(error))")
            }
        }

        if track.isStreaming, let cache,
           let cached = await cache.cachedAudio(for: track, quality: track.audioQuality) {
            do {
                log?("play start id=\(track.id) source=\(track.source.rawValue) via=cache \(urlSummary(cached.url))")
                try await engine.load(url: cached.url, contentType: nil)
                engine.play()
                state = .playing
                format = mergedFormat(stored: cached.format, measured: format)
                if let cachedDuration = cached.duration, cachedDuration > 0 {
                    duration = cachedDuration
                }
                currentItemIsLocal = true
                isCurrentFromCache = true
                playbackStartedAt = now()
                if forLoop { log?("loop source=cache") }
                onTrackStarted?(track)
                return
            } catch {
                // A damaged cache entry must not stop playback; resolve the stream instead.
                log?("cache hit unusable track=\(track.id) error=\(describe(error))")
            }
        }
        if forLoop { log?("loop source=network reason=cache-miss") }

        do {
            let url = try await resolver.url(for: track)
            let contentType = await resolver.contentType(for: track)
            log?("play start id=\(track.id) source=\(track.source.rawValue) via=network \(urlSummary(url))")
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
            playbackStartedAt = now()
            onTrackStarted?(track)
        } catch {
            pendingCache = nil
            log?("play failed id=\(track.id) error=\(describe(error))")
            if !retrying, track.isStreaming, !didRetryCurrentTrack {
                didRetryCurrentTrack = true
                // AVFoundation can refuse the extensionless catalog stream even when
                // the same bytes download fine; stage it and let the retry play locally.
                switch await stageInCacheForRetry(track) {
                case true?:
                    // The user may have skipped while the download was running.
                    guard queue.current?.id == track.id else {
                        log?("play retry aborted id=\(track.id) reason=stale")
                        return
                    }
                    await loadCurrent(retrying: true, forLoop: forLoop)
                case false?:
                    // The download failed too; the direct URL will not behave better.
                    state = .failed(error.localizedDescription)
                    log?("play state=failed id=\(track.id)")
                case nil:
                    await loadCurrent(retrying: true, forLoop: forLoop)
                }
            } else {
                state = .failed(error.localizedDescription)
                log?("play state=failed id=\(track.id)")
            }
        }
    }

    /// Stages the stream through the cache downloader so the retry can play a
    /// local file. Returns nil when this track cannot be staged, true when a cache
    /// hit is ready, false when the download itself failed.
    private func stageInCacheForRetry(_ track: Track) async -> Bool? {
        guard let cache else { return nil }
        do {
            let url = try await resolver.url(for: track)
            let contentType = await resolver.contentType(for: track)
            guard CacheEligibility.isCacheable(url: url, contentType: contentType) else {
                log?("play retry skip id=\(track.id) reason=uncacheable")
                return nil
            }
            log?("play retry id=\(track.id) via=download \(urlSummary(url))")
            cacheDownloadTrack = track
            await cache.store(
                track,
                quality: track.audioQuality,
                url: url,
                contentType: contentType,
                format: nil,
                duration: track.durationSeconds
            )
            cacheDownloadTrack = nil
            let staged = await cache.cachedAudio(for: track, quality: track.audioQuality) != nil
            log?("play retry staged id=\(track.id) ok=\(staged)")
            return staged
        } catch {
            log?("play retry skip id=\(track.id) error=\(describe(error))")
            return nil
        }
    }

    private func urlSummary(_ url: URL) -> String {
        if url.isFileURL {
            return "host=local path=\(url.lastPathComponent) hasQuery=false"
        }
        return "host=\(url.host ?? "none") path=\(url.path) hasQuery=\(url.query != nil)"
    }

    private func describe(_ error: any Error) -> String {
        var parts: [String] = []
        var current: NSError? = error as NSError
        var depth = 0
        while let nsError = current, depth < 5 {
            parts.append("\(nsError.domain)/\(nsError.code) \(nsError.localizedDescription)")
            current = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
            depth += 1
        }
        return parts.joined(separator: " <- ")
    }
}

extension PlayerController: RemoteCommandTarget {}
