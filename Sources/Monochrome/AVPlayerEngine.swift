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
    private var bufferEmptyObservation: NSKeyValueObservation?
    private var likelyToKeepUpObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    /// Set while `load` waits for the item, so the status observer does not race it.
    private var isWaitingForReadiness = false

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
        playerLog.notice("load start \(describeURL(url), privacy: .public) type=\(contentType ?? "none", privacy: .public)")
        // The catalog host serves FLAC as application/octet-stream without a path
        // extension, which leaves AVFoundation unable to pick a parser on its own.
        var options: [String: Any] = [:]
        if let contentType {
            options[overrideMIMETypeKey] = contentType
        }
        let asset = AVURLAsset(url: url, options: options)

        let item = AVPlayerItem(asset: asset)
        stopObservingItem()
        // Set before the initial observation fires: a failed item must be thrown
        // from this method, not relayed a second time as a mid-playback failure.
        isWaitingForReadiness = true
        defer { isWaitingForReadiness = false }
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
            playerLog.notice(
                "item.status=\(status, privacy: .public) error=\(describe(item.error), privacy: .public)"
            )
            guard item.status == .failed else { return }
            logAccessLog(item)
            logErrorLog(item)
            // Mid-playback failures reach the controller here; initial-load failures
            // are thrown from `load` so the retry path stays in one place.
            Task { @MainActor [weak self] in
                guard let self, !self.isWaitingForReadiness else { return }
                self.relay.send(.failed(item.error?.localizedDescription ?? "Playback failed."))
            }
        }
        bufferEmptyObservation = item.observe(\.isPlaybackBufferEmpty, options: [.new]) { item, _ in
            playerLog.notice(
                "item.bufferEmpty=\(item.isPlaybackBufferEmpty, privacy: .public) likelyToKeepUp=\(item.isPlaybackLikelyToKeepUp, privacy: .public) status=\(item.status.rawValue, privacy: .public)"
            )
        }
        likelyToKeepUpObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { item, _ in
            playerLog.notice(
                "item.likelyToKeepUp=\(item.isPlaybackLikelyToKeepUp, privacy: .public) bufferEmpty=\(item.isPlaybackBufferEmpty, privacy: .public) status=\(item.status.rawValue, privacy: .public)"
            )
        }
        player.replaceCurrentItem(with: item)
        playerLog.notice("replaced current item")

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
                logItemSnapshot("item failed during load", item: item)
                logFailure("item failed during load", error)
                asset.cancelLoading()
                throw error
            default:
                if waited >= readinessTimeout {
                    let underlying = item.error
                    logItemSnapshot("item not ready after timeout", item: item)
                    logAccessLog(item)
                    logErrorLog(item)
                    logFailure("item timed out during load", underlying ?? EngineError.timedOut(underlying: nil))
                    // Stop the pending load before throwing so a retry cannot leave
                    // two items fetching the same stream.
                    stopObservingItem()
                    asset.cancelLoading()
                    player.replaceCurrentItem(with: nil)
                    throw EngineError.timedOut(underlying: underlying)
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
        player.replaceCurrentItem(with: nil)
        playerLog.notice("stopped")
    }

    /// The codec and sample format AVFoundation parsed, not what the URL claimed.
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
        bufferEmptyObservation = nil
        likelyToKeepUpObservation = nil
    }

    private func logFailure(_ message: String, _ error: any Error) {
        playerLog.error("\(message, privacy: .public) \(describe(error), privacy: .public)")
    }

    private func logItemSnapshot(_ message: String, item: AVPlayerItem) {
        playerLog.error(
            "\(message, privacy: .public) status=\(item.status.rawValue) likelyToKeepUp=\(item.isPlaybackLikelyToKeepUp, privacy: .public) bufferEmpty=\(item.isPlaybackBufferEmpty, privacy: .public) timeControl=\(self.player.timeControlStatus.rawValue) waiting=\(self.player.reasonForWaitingToPlay?.rawValue ?? "none", privacy: .public) error=\(describe(item.error), privacy: .public)"
        )
    }
}

/// The complete error chain, including nested underlying errors.
private func describe(_ error: (any Error)?) -> String {
    guard let error else { return "none" }
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

/// Host and path only: query strings may carry identifiers and never belong in logs.
private func describeURL(_ url: URL) -> String {
    if url.isFileURL {
        return "host=local path=\(url.lastPathComponent) hasQuery=false"
    }
    return "host=\(url.host ?? "none") path=\(url.path) hasQuery=\(url.query != nil)"
}

private func redact(_ uri: String?) -> String {
    guard let uri, let url = URL(string: uri) else { return uri ?? "none" }
    return describeURL(url)
}

/// FourCC as text, e.g. `flac`; trimming keeps `aac ` and `.mp3` readable.
private func fourCharacterCode(_ code: FourCharCode) -> String {
    let bytes: [UInt8] = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
    return String(decoding: bytes, as: UTF8.self)
}

/// `AVPlayerItemErrorLog` carries the HTTP-level reason behind a -11828.
private func logErrorLog(_ item: AVPlayerItem) {
    guard let log = item.errorLog(), !log.events.isEmpty else {
        playerLog.error("errorLog empty")
        return
    }
    for event in log.events {
        playerLog.error(
            "errorLog status=\(event.errorStatusCode) domain=\(event.errorDomain, privacy: .public) comment=\(event.errorComment ?? "none", privacy: .public) uri=\(redact(event.uri), privacy: .public)"
        )
    }
}

/// The access log shows what the HTTP layer actually received before the item failed.
private func logAccessLog(_ item: AVPlayerItem) {
    guard let log = item.accessLog(), !log.events.isEmpty else {
        playerLog.notice("accessLog empty")
        return
    }
    for event in log.events {
        playerLog.notice(
            "accessLog bytes=\(event.numberOfBytesTransferred) mediaRequests=\(event.numberOfMediaRequests) stalls=\(event.numberOfStalls) startup=\(event.startupTime) observedBitrate=\(event.observedBitrate) indicatedBitrate=\(event.indicatedBitrate) uri=\(redact(event.uri), privacy: .public)"
        )
    }
}

enum EngineError: LocalizedError, CustomNSError {
    case unreadable
    case timedOut(underlying: (any Error)?)

    static var errorDomain: String { "Monochrome.EngineError" }

    var errorCode: Int {
        switch self {
        case .unreadable: 1
        case .timedOut: 2
        }
    }

    var errorDescription: String? {
        switch self {
        case .unreadable:
            "This file could not be played. It may be corrupted or use an unsupported format."
        case .timedOut:
            "The stream did not start. Check the connection, then retry."
        }
    }

    var errorUserInfo: [String: Any] {
        var info: [String: Any] = [NSLocalizedDescriptionKey: errorDescription ?? ""]
        if case .timedOut(let underlying) = self, let underlying {
            info[NSUnderlyingErrorKey] = underlying
        }
        return info
    }
}
#endif
