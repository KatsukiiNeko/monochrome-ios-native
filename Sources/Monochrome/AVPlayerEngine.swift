// AVPlayerEngine.swift: PlaybackEngine backed by AVPlayer, main-actor confined.
#if canImport(AVFoundation)
import AVFoundation
import Foundation
import MonochromeCore

@MainActor
final class AVPlayerEngine: PlaybackEngine {
    var onEvent: ((PlaybackEvent) -> Void)? {
        didSet { relay.send = onEvent }
    }

    private let player = AVPlayer()
    private let relay = EventRelay()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?

    init() {
        // AVPlayer callbacks arrive on the main queue; hand them to the controller there.
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [relay] time in
            let seconds = time.seconds
            Task { @MainActor in relay.send?(.position(seconds)) }
        }
    }

    func load(url: URL) async throws {
        let asset = AVURLAsset(url: url)
        let playable: Bool
        do {
            playable = try await asset.load(.isPlayable)
        } catch {
            throw EngineError.unreadable
        }
        guard playable else { throw EngineError.unreadable }

        let item = AVPlayerItem(asset: asset)
        stopObservingItem()
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [relay] _ in
            Task { @MainActor in relay.send?(.finished) }
        }
        failureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
        ) { [relay] notification in
            let message = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?
                .localizedDescription ?? "Playback failed."
            Task { @MainActor in relay.send?(.failed(message)) }
        }
        player.replaceCurrentItem(with: item)

        if let duration = try? await asset.load(.duration), duration.isNumeric {
            onEvent?(.ready(duration: duration.seconds))
        }
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
    }

    func stop() {
        player.pause()
        stopObservingItem()
        player.replaceCurrentItem(with: nil)
    }

    private func stopObservingItem() {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        endObserver = nil
        failureObserver = nil
    }
}

enum EngineError: LocalizedError {
    case unreadable

    var errorDescription: String? {
        "This file could not be played. It may be corrupted or use an unsupported format."
    }
}

/// AVFoundation callbacks are not main-actor annotated, so they forward through
/// this box instead of capturing the engine from a @Sendable closure.
private final class EventRelay: @unchecked Sendable {
    var send: ((PlaybackEvent) -> Void)?
}
#endif
