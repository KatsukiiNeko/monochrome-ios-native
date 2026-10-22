// AVPlayerEngine.swift: PlaybackEngine backed by AVPlayer, main-actor confined.
#if canImport(AVFoundation)
import AVFoundation
import Foundation
import MonochromeCore
import os

/// One shared logger so device logs can be filtered by subsystem/category.
let playerLog = Logger(subsystem: "com.neko-ngtran.monochrome", category: "player")

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

    func load(url: URL) async throws {
        playerLog.notice("load start url=\(url.absoluteString, privacy: .public)")
        let asset = AVURLAsset(url: url)
        let playable: Bool
        do {
            playable = try await asset.load(.isPlayable)
        } catch {
            logFailure("asset isPlayable threw", error)
            throw EngineError.unreadable
        }
        playerLog.notice("asset isPlayable=\(playable, privacy: .public)")
        guard playable else { throw EngineError.unreadable }

        let item = AVPlayerItem(asset: asset)
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
        statusObservation = item.observe(\.status, options: [.initial, .new]) { item, _ in
            let status = item.status.rawValue
            playerLog.notice("item.status=\(status, privacy: .public)")
            if item.status == .failed {
                playerLog.error("item error: \(describe(item.error), privacy: .public)")
                logErrorLog(item)
            }
        }
        player.replaceCurrentItem(with: item)
        playerLog.notice("replaced current item")

        do {
            let duration = try await asset.load(.duration)
            playerLog.notice("asset duration numeric=\(duration.isNumeric, privacy: .public) seconds=\(duration.seconds)")
            if duration.isNumeric {
                onEvent?(.ready(duration: duration.seconds))
            }
        } catch {
            logFailure("asset duration threw", error)
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

    var errorDescription: String? {
        "This file could not be played. It may be corrupted or use an unsupported format."
    }
}
#endif
