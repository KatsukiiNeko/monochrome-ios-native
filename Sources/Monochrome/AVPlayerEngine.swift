// AVPlayerEngine.swift: PlaybackEngine backed by AVPlayer, main-actor confined.
#if canImport(AVFoundation)
import AVFoundation
import Foundation
import MonochromeCore
import os

/// One shared logger so device logs can be filtered by subsystem/category.
let playerLog = Logger(subsystem: "com.neko-ngtran.monochrome", category: "player")

/// AVFoundation's public key for the MIME type of an extensionless resource.
private let overrideMIMETypeKey = AVURLAssetOverrideMIMETypeKey
/// Upper bound for the item to become ready; AVFoundation has no timeout of its own.
private let readinessTimeout = Duration.seconds(20)
private let readinessPollInterval = Duration.milliseconds(100)

@MainActor
final class AVPlayerEngine: PlaybackEngine {
    var onEvent: ((PlaybackEvent) -> Void)? {
        didSet { relay.handler = onEvent }
    }

    private let player = AVPlayer()
    private let relay = CallbackRelay<PlaybackEvent>()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    /// Set while `load` waits for the item, so the status observer does not race it.
    private var isWaitingForReadiness = false
    private var eqTapStorage: EQTapStorage?
    private var eqTap: MTAudioProcessingTap?
    private var eqFrameLogTask: Task<Void, Never>?
    private var loggedEQFormat = false
    /// Whether the current item can carry the equalizer tap.
    private(set) var eqAvailability: EQAvailability = .unavailable(.noAudioTrack)

    init() {
        // AVPlayer callbacks arrive on the main queue; hand them to the controller there.
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [relay] time in
            relay.send(.position(time.seconds))
        }
        timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { player, _ in
            let status = player.timeControlStatus.rawValue
            let reason = player.reasonForWaitingToPlay?.rawValue ?? "none"
            playerLog.notice(
                "timeControlStatus=\(status, privacy: .public) waitingReason=\(reason, privacy: .public)"
            )
        }
    }

    func load(url: URL, contentType: String?) async throws {
        playerLog.notice("load start url=\(url.absoluteString, privacy: .public) type=\(contentType ?? "none", privacy: .public)")
        // The catalog host serves FLAC as application/octet-stream without a path
        // extension, which leaves AVFoundation unable to pick a parser on its own.
        var options: [String: Any] = [:]
        if let contentType {
            options[overrideMIMETypeKey] = contentType
        }
        let asset = AVURLAsset(url: url, options: options)

        // The tap needs the item's audio track before the item reaches the
        // player, otherwise the first buffers bypass the chain entirely.
        let audioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        let item = AVPlayerItem(asset: asset)
        attachEQTap(to: item, audioTracks: audioTracks, url: url, contentType: contentType)
        stopObservingItem()
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [relay] _ in
            playerLog.notice("item reached end")
            relay.send(.finished)
        }
        failureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
        ) { [relay] notification in
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            playerLog.error("item failed to play to end: \(describe(error), privacy: .public)")
            relay.send(.failed(error?.localizedDescription ?? "Playback failed."))
        }
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            let status = item.status.rawValue
            playerLog.notice("item.status=\(status, privacy: .public)")
            guard item.status == .failed else { return }
            let error = item.error
            playerLog.error("item error: \(describe(error), privacy: .public)")
            logErrorLog(item)
            // Mid-playback failures reach the controller here; initial-load failures
            // are thrown from `load` so the retry path stays in one place.
            Task { @MainActor [weak self] in
                guard let self, !self.isWaitingForReadiness else { return }
                self.relay.send(.failed(error?.localizedDescription ?? "Playback failed."))
            }
        }
        player.replaceCurrentItem(with: item)
        playerLog.notice("replaced current item")

        isWaitingForReadiness = true
        defer { isWaitingForReadiness = false }
        var waited = Duration.zero
        while true {
            switch item.status {
            case .readyToPlay:
                let duration = item.duration.isNumeric ? item.duration.seconds : nil
                let format = await audioFormat(of: asset)
                playerLog.notice(
                    "item ready seconds=\(duration ?? -1) codec=\(format?.codec ?? "none", privacy: .public) depth=\(format?.bitDepth ?? 0) rate=\(format?.sampleRateHz ?? 0)"
                )
                if let format {
                    playerLog.notice(
                        "audiospec measured codec=\(format.codec, privacy: .public) sr=\(format.sampleRateHz ?? 0) ch=\(format.channels ?? 0) bitrate=\(format.bitrateKbps ?? 0)"
                    )
                }
                onEvent?(.ready(duration: duration, format: format))
                return
            case .failed:
                let error = item.error ?? EngineError.unreadable
                logFailure("item failed during load", error)
                throw error
            default:
                if waited >= readinessTimeout {
                    playerLog.error("item not ready after timeout")
                    throw EngineError.timedOut
                }
                try await Task.sleep(for: readinessPollInterval)
                waited += readinessPollInterval
            }
        }
    }

    func play() {
        player.play()
        playerLog.notice("play requested")
    }

    func pause() {
        player.pause()
        playerLog.notice("pause requested")
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        playerLog.notice("seek requested seconds=\(seconds)")
    }

    func stop() {
        player.pause()
        stopObservingItem()
        eqFrameLogTask?.cancel()
        eqFrameLogTask = nil
        eqTap = nil
        eqTapStorage = nil
        player.replaceCurrentItem(with: nil)
        playerLog.notice("stopped")
    }

    /// Attaches a pass-through tap when the item can carry one. HLS is rejected
    /// by `AVPlayerItem.audioMix`, so the availability check happens first.
    private func attachEQTap(
        to item: AVPlayerItem,
        audioTracks: [AVAssetTrack],
        url: URL,
        contentType: String?
    ) {
        eqFrameLogTask?.cancel()
        eqFrameLogTask = nil
        eqTap = nil
        eqTapStorage = nil
        loggedEQFormat = false
        eqAvailability = EQAvailability.resolve(
            url: url,
            contentType: contentType,
            hasAudioTrack: !audioTracks.isEmpty
        )
        guard case .available = eqAvailability, let track = audioTracks.first else {
            if case .unavailable(let reason) = eqAvailability {
                playerLog.notice("eq unavailable reason=\(reason.rawValue, privacy: .public)")
            }
            return
        }
        let storage = EQTapStorage()
        guard let tap = EQTap.make(storage: storage) else { return }
        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]
        item.audioMix = mix
        eqTapStorage = storage
        eqTap = tap
        startEQFrameLog()
        playerLog.notice("eq tap attached")
    }

    /// Logs the frame counter from the main actor; the audio thread only
    /// increments it.
    private func startEQFrameLog() {
        eqFrameLogTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, let storage = self.eqTapStorage else { return }
                let snapshot = storage.snapshot
                if let format = snapshot.format, !self.loggedEQFormat {
                    self.loggedEQFormat = true
                    playerLog.notice(
                        "eq tap prepare sr=\(format.sampleRate) ch=\(format.channelCount) interleaved=\(format.isInterleaved)"
                    )
                }
                playerLog.notice("eq tap frames=\(snapshot.frames)")
            }
        }
    }


    private func audioFormat(of asset: AVURLAsset) async -> AudioFormat? {
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let descriptions = try? await track.load(.formatDescriptions),
              let description = descriptions.first
        else { return nil }
        let codec = fourCharacterCode(CMFormatDescriptionGetMediaSubType(description))
        let estimatedDataRate = (try? await track.load(.estimatedDataRate)) ?? 0
        let bitrateKbps = estimatedDataRate > 0 ? Int((estimatedDataRate / 1000).rounded()) : nil
        guard let stream = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee else {
            return AudioFormat(codec: codec, bitrateKbps: bitrateKbps, bitrateIsEstimated: true)
        }
        let depth = Int(stream.mBitsPerChannel)
        let rate = Int(stream.mSampleRate)
        let channels = Int(stream.mChannelsPerFrame)
        return AudioFormat(
            codec: codec,
            bitDepth: depth > 0 ? depth : nil,
            sampleRateHz: rate > 0 ? rate : nil,
            channels: channels > 0 ? channels : nil,
            bitrateKbps: bitrateKbps,
            bitrateIsEstimated: bitrateKbps == nil ? nil : true
        )
    }

    private func stopObservingItem() {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        endObserver = nil
        failureObserver = nil
        statusObservation = nil
    }

    private func logFailure(_ message: String, _ error: any Error) {
        let nsError = error as NSError
        playerLog.error(
            "\(message, privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code) description=\(nsError.localizedDescription, privacy: .public)"
        )
    }
}

private func describe(_ error: (any Error)?) -> String {
    guard let error else { return "none" }
    let nsError = error as NSError
    let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
    var text = "domain=\(nsError.domain) code=\(nsError.code) description=\(nsError.localizedDescription)"
    if let underlying {
        text += " underlying=\(underlying.domain)/\(underlying.code) \(underlying.localizedDescription)"
    }
    return text
}

/// FourCC as text, e.g. `flac`; trimming keeps `aac ` and `.mp3` readable.
private func fourCharacterCode(_ code: FourCharCode) -> String {
    let bytes: [UInt8] = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
    return String(decoding: bytes, as: UTF8.self)
}

/// `AVPlayerItemErrorLog` carries the HTTP-level reason behind a -11828.
private func logErrorLog(_ item: AVPlayerItem) {
    guard let log = item.errorLog() else {
        playerLog.error("no error log available")
        return
    }
    for event in log.events {
        playerLog.error(
            "errorLog status=\(event.errorStatusCode) domain=\(event.errorDomain, privacy: .public) comment=\(event.errorComment ?? "none", privacy: .public) uri=\(event.uri ?? "none", privacy: .public)"
        )
    }
}

enum EngineError: LocalizedError {
    case unreadable
    case timedOut

    var errorDescription: String? {
        switch self {
        case .unreadable:
            "This file could not be played. It may be corrupted or use an unsupported format."
        case .timedOut:
            "The stream did not start. Check the connection, then retry."
        }
    }
}
#endif
