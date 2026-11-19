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
    /// Bumped by every seek, so observers wake even when the position repeats.
    public private(set) var seekCount = 0
    /// Parsed format of the current stream; nil until the item is ready.
    public private(set) var format: AudioFormat?
    /// Repeat control; `one` restarts the current track at its end.
    public private(set) var repeatMode: RepeatMode = .off
    /// True while the queue order is shuffled; toggling off restores the order
    /// the queue had when shuffle was enabled.
    public private(set) var isShuffled = false
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
    /// Called once when the current track passes halfway, so the next network
    /// track can be staged into the cache. Nil disables preparation.
    public var onPastHalfway: ((Track) -> Void)?
    /// Called when a track is heard to the end, left early or looped; the app
    /// forwards these to the listening log.
    public var onPlayEvent: (@MainActor (PlayEvent) -> Void)?
    /// Technical log sink; the app forwards these to os.Logger.
    public var log: ((String) -> Void)?

    private let engine: any PlaybackEngine
    private let resolver: any TrackURLResolver
    private let cache: (any AudioCaching)?
    private let downloads: (any DownloadedAudioProviding)?
    private let sessionStore: PlaybackSessionStore?
    /// Optional cheap check that the stream answers before an asset is built.
    private let preflight: (any StreamPreflighting)?
    private let now: @Sendable () -> Date
    /// A download may be cancelled only while the track has just started.
    private static let skipCancellationWindow: TimeInterval = 10
    /// One fresh resolution per track after a failure, then the error is shown.
    private var didRetryCurrentTrack = false
    /// True while the engine holds a file, so a restart needs no network round trip.
    private var currentItemIsLocal = false
    private var didPrepareNextForCurrentTrack = false
    /// Stream resolved for the current item, waiting for the parsed format before caching.
    private var pendingCache: PendingCache?
    /// When the current item started, used to decide whether skipping should cancel its cache.
    private var playbackStartedAt: Date?
    /// True when the current track reached its end; a finished track is not
    /// reported as skipped.
    private var didFinishCurrentTrack = false
    /// Cancels the running preflight when a newer load supersedes it.
    private var cancellation: AttemptCancellation?
    /// Numbers every attempt to start a track; a stale attempt drops its results.
    private var ownership = PlaybackOwnership()
    /// The track whose background download belongs to the current item.
    private var cacheDownloadTrack: Track?
    private var sleepTimerTask: Task<Void, Never>?
    /// Queue order before shuffle; only valid while `isShuffled` is true.
    private var unshuffledTracks: [Track] = []

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
        sessionStore: PlaybackSessionStore? = nil,
        preflight: (any StreamPreflighting)? = nil,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.engine = engine
        self.resolver = resolver
        self.cache = cache
        self.downloads = downloads
        self.sessionStore = sessionStore
        self.preflight = preflight
        self.now = now
        if sessionStore != nil {
            Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(10))
                    guard let self else { return }
                    await MainActor.run { self.saveSession() }
                }
            }
        }
        engine.onEvent = { [weak self] tagged in
            self?.handle(tagged)
        }
    }

    // MARK: - Commands

    public func play(tracks: [Track], startingAt index: Int) async {
        reportAbandonedTrack()
        queue.replace(with: tracks, startingAt: index)
        // A replaced queue is a fresh listening session.
        isShuffled = false
        unshuffledTracks = []
        await loadCurrent()
    }

    /// Fisher-Yates over the queue with the current track pinned in place, so
    /// playback never restarts. Toggling off restores the pre-shuffle order.
    public func toggleShuffle(generator: (Int) -> Int = { Int.random(in: 0..<$0) }) {
        guard !queue.isEmpty else { return }
        if isShuffled {
            let currentID = queue.current?.id
            queue.replace(with: unshuffledTracks, startingAt: 0)
            if let currentID, let index = queue.tracks.firstIndex(where: { $0.id == currentID }) {
                queue.pin(at: index)
            }
            isShuffled = false
            unshuffledTracks = []
        } else {
            unshuffledTracks = queue.tracks
            let shuffled = QueueShuffle.shuffled(
                queue.tracks,
                pinIndex: queue.currentIndex,
                generator: generator
            )
            queue.replace(with: shuffled, startingAt: queue.currentIndex ?? 0)
            isShuffled = true
        }
    }

    /// Plays a track right after the current one; with no current track it starts.
    public func playNext(_ track: Track) {
        let index = queue.currentIndex.map { $0 + 1 } ?? 0
        queue.insert(track, at: index)
    }

    public func togglePlayPause() async {
        switch state {
        case .playing:
            engine.pause()
            state = .paused
        case .paused:
            engine.play()
            state = .playing
        case .idle, .failed, .stopped:
            await retry()
        case .loading:
            break
        }
    }

    public func next() async {
        reportAbandonedTrack()
        if queue.advance() != nil {
            await loadCurrent()
        } else {
            ownership.invalidateAll()
            await cancelCacheDownloadIfSkippedEarly()
            playbackStartedAt = nil
            cacheDownloadTrack = nil
            engine.stop()
            position = 0
            state = .stopped(.endOfQueue)
            log?("[Playback] stop reason=endOfQueue")
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
            return
        }
        let abandoned = queue.current
        guard queue.rewind() != nil else {
            engine.seek(to: 0)
            position = 0
            return
        }
        reportAbandonedTrack(abandoned)
        await loadCurrent()
    }

    public func seek(to seconds: Double) {
        guard queue.current != nil else { return }
        let clamped = max(0, duration > 0 ? min(seconds, duration) : seconds)
        position = clamped
        seekCount += 1
        engine.seek(to: clamped)
    }

    public func jump(to index: Int) async {
        let abandoned = queue.current
        guard queue.jump(to: index) != nil else { return }
        reportAbandonedTrack(abandoned)
        await loadCurrent()
    }

    public func append(_ tracks: [Track]) {
        queue.append(tracks)
    }

    public func removeTrack(at index: Int) async {
        let removedCurrent = queue.current?.id
        guard let removed = queue.remove(at: index) else { return }
        if removed.id == removedCurrent {
            reportAbandonedTrack(removed)
            await loadCurrent()
        }
    }

    public func moveQueue(from source: Int, to destination: Int) {
        queue.move(from: source, to: destination)
    }

    /// Stops playback and empties the queue.
    public func clearQueue() {
        reportAbandonedTrack()
        ownership.invalidateAll()
        engine.stop()
        position = 0
        duration = 0
        state = .stopped(.queueCleared)
        log?("[Playback] stop reason=queueCleared")
        queue = Queue()
        isShuffled = false
        unshuffledTracks = []
        isCurrentFromCache = false
        isCurrentFromDownload = false
        currentItemIsLocal = false
        pendingCache = nil
        cacheDownloadTrack = nil
    }

    /// Persists the current queue and position for restoration after a restart.
    public func saveSession() {
        guard let store = sessionStore, let track = queue.current else { return }
        let session = PlaybackSession(
            tracks: queue.tracks,
            currentIndex: queue.currentIndex,
            position: position,
            isShuffled: isShuffled,
            repeatMode: repeatMode,
            radioRunning: false,
            savedAt: now()
        )
        store.save(session)
    }

    /// Restores a saved queue without auto-playing.
    public func restoreSession(_ session: PlaybackSession) async {
        guard !session.tracks.isEmpty else { return }
        queue.replace(with: session.tracks, startingAt: session.currentIndex ?? 0)
        isShuffled = session.isShuffled
        repeatMode = session.repeatMode
        await loadCurrent(autoPlay: false)
        seek(to: session.position)
    }

    /// User-initiated retry, including a fresh stream resolution.
    public func retry() async {
        guard queue.current != nil else { return }
        didRetryCurrentTrack = false
        await loadCurrent()
    }

    /// Forwards the current equalizer settings to the engine, which applies them
    /// to the running item when it can.
    public func setEqualizer(_ settings: EQSettings) {
        engine.setEqualizer(settings)
    }

    public var eqAvailability: EQAvailability { engine.eqAvailability }

    /// Reads and clears the clip light counter.
    public func takeEqualizerPeak() -> Double {
        engine.takeEqualizerPeak()
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

    /// Events arrive on the main actor in order. Stale attempts die here, before
    /// any state changes. Only the two events that need playback work start a
    /// task; those tasks run one after another, never concurrently.
    func handle(_ tagged: PlaybackEngineEvent) {
        let accepted = ownership.owns(tagged.token)
        if case .position = tagged.event {
            // Ticks once a second; logging them would drown the useful lines.
        } else {
            log?("[Playback] event g=\(tagged.token.value) kind=\(tagged.event.kind) accepted=\(accepted)")
        }
        guard accepted else { return }
        switch tagged.event {
        case .ready(let engineDuration, let engineFormat):
            handleReady(duration: engineDuration, format: engineFormat)
        case .position(let seconds):
            position = seconds
            triggerNextTrackPreparationIfNeeded()
        case .finished:
            enqueue { [weak self] in await self?.handleEndOfTrack(token: tagged.token) }
        case .failed(let message):
            enqueue { [weak self] in await self?.handleFailure(message, token: tagged.token) }
        }
    }

    /// A single serial queue for event work, so a finished event cannot overtake
    /// the failure or reload that follows it.
    private var eventTask: Task<Void, Never>?
    private var eventGeneration = 0

    private func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        eventGeneration += 1
        let previous = eventTask
        eventTask = Task { @MainActor in
            await previous?.value
            await operation()
        }
    }

    /// Test hook: wait until every queued event task has finished.
    func waitForPendingEvents() async {
        while true {
            let generation = eventGeneration
            guard let task = eventTask else { return }
            await task.value
            if eventGeneration == generation { return }
        }
    }

    // MARK: - Internals

    private static func preflightDetail(_ result: PreflightResult) -> String {
        let status = result.lastStatus.map(String.init) ?? "none"
        return "status=\(status) requests=\(result.requestCount) ready=\(result.isReady)"
    }

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

    private func triggerNextTrackPreparationIfNeeded() {
        guard !didPrepareNextForCurrentTrack else { return }
        guard let handler = onPastHalfway else { return }
        guard let next = nextNetworkTrack() else { return }
        let hasNext = true
        guard NextTrackPreparation.shouldPrepare(
            currentPosition: position,
            duration: duration,
            hasNextTrack: hasNext,
            isPreparing: false,
            isUnmeteredWiFi: true,
            isInBackground: false,
            nextIsNetwork: next.isStreaming
        ) else { return }
        didPrepareNextForCurrentTrack = true
        handler(next)
    }

    private func nextNetworkTrack() -> Track? {
        guard let currentIndex = queue.currentIndex,
              currentIndex + 1 < queue.tracks.count else { return nil }
        return queue.tracks[currentIndex + 1]
    }

    private func handleFailure(_ message: String, token: PlaybackToken) async {
        guard ownership.owns(token) else { return }
        // A stream can expire mid-playback; resolve once more before giving up.
        if queue.current?.isStreaming == true, !didRetryCurrentTrack {
            didRetryCurrentTrack = true
            await loadCurrent(retrying: true)
        } else {
            state = .failed(message)
        }
    }

    private func handleEndOfTrack(token: PlaybackToken) async {
        guard ownership.owns(token) else { return }
        let hasNext = queue.currentIndex.map { $0 + 1 < queue.tracks.count } ?? false
        let action = EndOfTrackDecision.action(
            repeatMode: repeatMode,
            hasNext: hasNext,
            hasTracks: !queue.isEmpty,
            itemIsLocal: currentItemIsLocal
        )
        didFinishCurrentTrack = true
        reportCompletedTrack(loop: action == .replayInPlace || action == .reload)
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
            ownership.invalidateAll()
            engine.stop()
            position = 0
            state = .stopped(.endOfQueue)
            log?("[Playback] stop reason=endOfQueue")
            isCurrentFromCache = false
            isCurrentFromDownload = false
            currentItemIsLocal = false
        }
    }

    /// Reports the track that was left before its end; a track that reached
    /// the end was already reported as completed.
    private func reportAbandonedTrack(_ track: Track? = nil) {
        guard !didFinishCurrentTrack, let track = track ?? queue.current else { return }
        guard state == .playing || state == .paused else { return }
        didFinishCurrentTrack = true
        onPlayEvent?(PlayEvent(
            source: track.provider,
            trackID: track.id,
            artist: track.artist,
            album: track.album,
            startedAt: playbackStartedAt ?? now(),
            listenedSeconds: position,
            duration: duration,
            outcome: .skipped
        ))
    }

    /// Reports a track that was heard to the end; a loop counts as a replay.
    private func reportCompletedTrack(loop: Bool) {
        guard let track = queue.current else { return }
        onPlayEvent?(PlayEvent(
            source: track.provider,
            trackID: track.id,
            artist: track.artist,
            album: track.album,
            startedAt: playbackStartedAt ?? now(),
            listenedSeconds: duration > 0 ? duration : position,
            duration: duration,
            outcome: .completed,
            loop: loop
        ))
    }

    /// True while this attempt is still the newest and the queue still names its
    /// track. A stale attempt clears only its own pending cache and says nothing.
    private func stillOwns(_ token: PlaybackToken, _ track: Track) -> Bool {
        guard ownership.owns(token), queue.current?.id == track.id else {
            if pendingCache?.track.id == track.id { pendingCache = nil }
            log?("[Playback] drop g=\(token.value) track=\(track.id.prefix(8)) reason=superseded")
            return false
        }
        return true
    }

    private func loadCurrent(retrying: Bool = false, forLoop: Bool = false, autoPlay: Bool = true) async {
        let token = ownership.begin()
        await cancelCacheDownloadIfSkippedEarly()
        if let cache { await cache.clearProtection() }
        playbackStartedAt = nil
        guard let track = queue.current else {
            if state != .idle {
                log?("[Playback] queue-empty while phase=\(state.logName) reason=endOfQueue")
            }
            engine.stop()
            state = .stopped(.endOfQueue)
            position = 0
            duration = 0
            currentItemIsLocal = false
            isCurrentFromCache = false
            isCurrentFromDownload = false
            pendingCache = nil
            return
        }
        guard stillOwns(token, track) else { return }
        log?("[Playback] begin g=\(token.value) track=\(track.id.prefix(8))")
        if !retrying { didRetryCurrentTrack = false }
        cancellation?.cancel()
        let attemptCancellation = AttemptCancellation()
        cancellation = attemptCancellation

        state = .loading(autoPlay: autoPlay)
        format = nil
        position = 0
        duration = track.durationSeconds ?? 0
        didFinishCurrentTrack = false
        isCurrentFromCache = false
        isCurrentFromDownload = false
        pendingCache = nil

        var attempt = PlaybackAttemptLog(trackKey: track.sourceKey, at: now())
        defer { log?(attempt.summary) }

        if track.isStreaming, let downloads {
            let downloaded = await downloads.downloadedFile(for: track)
            attempt.mark(.lookup, at: now(), detail: downloaded == nil ? "download-miss" : "download-hit")
            guard stillOwns(token, track) else { return }
            if let downloaded {
                do {
                    attempt.mark(.asset, at: now(), detail: "download")
                    try await engine.load(url: downloaded.url, contentType: nil, headers: [:], token: token)
                    guard stillOwns(token, track) else { return }
                    if autoPlay { engine.play() }
                    state = autoPlay ? .playing : .paused
                    format = mergedFormat(stored: downloaded.format, measured: format)
                    if let downloadedDuration = downloaded.duration, downloadedDuration > 0 {
                        duration = downloadedDuration
                    }
                    currentItemIsLocal = true
                    isCurrentFromDownload = true
                    playbackStartedAt = now()
                    attempt.mark(.ready, at: now(), detail: "download")
                    if forLoop { log?("loop source=download") }
                    log?("download source=file track=\(track.id)")
                    if autoPlay { onTrackStarted?(track) }
                    return
                } catch is PlaybackSuperseded {
                    return
                } catch {
                    log?("download unusable track=\(track.id)")
                }
            }
        }

        if track.isStreaming, let cache {
            let cached = await cache.cachedAudio(for: track, quality: track.audioQuality)
            attempt.mark(.lookup, at: now(), detail: cached == nil ? "cache-miss" : "cache-hit")
            guard stillOwns(token, track) else { return }
            if let cached {
                do {
                    attempt.mark(.asset, at: now(), detail: "cache")
                    try await engine.load(url: cached.url, contentType: nil, headers: [:], token: token)
                    guard stillOwns(token, track) else { return }
                    if autoPlay { engine.play() }
                    state = autoPlay ? .playing : .paused
                    format = mergedFormat(stored: cached.format, measured: format)
                    if let cachedDuration = cached.duration, cachedDuration > 0 {
                        duration = cachedDuration
                    }
                    currentItemIsLocal = true
                    isCurrentFromCache = true
                    playbackStartedAt = now()
                    attempt.mark(.ready, at: now(), detail: "cache")
                    if forLoop { log?("loop source=cache") }
                    if autoPlay { onTrackStarted?(track) }
                    return
                } catch is PlaybackSuperseded {
                    return
                } catch {
                    // A damaged cache entry must not stop playback; resolve the stream instead.
                    log?("cache hit unusable track=\(track.id)")
                }
            }
        }
        if forLoop { log?("loop source=network reason=cache-miss") }

        do {
            let source = try await resolver.playbackSource(for: track)
            attempt.mark(.resolve, at: now())
            guard stillOwns(token, track) else { return }
            let url = source.url
            let resolvedContentType = await resolver.contentType(for: track)
            guard stillOwns(token, track) else { return }
            let contentType = source.contentType ?? resolvedContentType
            let headers = source.headers
            pendingCache = PendingCache(
                track: track,
                quality: source.quality ?? track.audioQuality,
                url: url,
                contentType: contentType
            )
            // Only a catalog retry is probed: the measured origin answers a ranged
            // request in 2-13 s, far past any probe timeout, so a cold probe says
            // nothing about whether the player can start the item. On a retry it
            // still warms DNS and the edge before the second attempt.
            if let preflight, retrying, !url.isFileURL, track.provider == MusicSourceID.monochrome.rawValue {
                let result = await preflight.waitUntilReady(
                    url: url,
                    isCancelled: { attemptCancellation.isCancelled }
                )
                attempt.countRequest("preflight", count: result.requestCount)
                attempt.mark(.preflight, at: now(), detail: Self.preflightDetail(result))
                guard stillOwns(token, track) else { return }
            }
            attempt.countRequest("item")
            attempt.mark(.asset, at: now(), detail: "network")
            try await engine.load(url: url, contentType: contentType, headers: headers, token: token)
            guard stillOwns(token, track) else { return }
            if autoPlay { engine.play() }
            state = autoPlay ? .playing : .paused
            currentItemIsLocal = source.isLocal
            playbackStartedAt = now()
            attempt.mark(.ready, at: now(), detail: "network")
            if autoPlay { onTrackStarted?(track) }
        } catch is PlaybackSuperseded {
            return
        } catch {
            attempt.mark(.failed, at: now(), detail: PlaybackAttemptLog.errorDetail(error))
            guard stillOwns(token, track) else { return }
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

extension PlayerController: RemoteCommandTarget {}
