// AudioSessionController.swift: playback audio session, interruptions and route changes.
#if canImport(AVFoundation)
import AVFoundation
import MonochromeCore
import os

private let sessionLog = Logger(subsystem: "com.neko-ngtran.monochrome", category: "audio-session")

@MainActor
final class AudioSessionController {
    private let player: PlayerController
    private let interruptionRelay = CallbackRelay<AudioInterruption>()
    private let routeRelay = CallbackRelay<RouteChange>()
    private var observers: [NSObjectProtocol] = []

    init(player: PlayerController) {
        self.player = player
        configure()
        interruptionRelay.handler = { [weak self] event in self?.handle(event) }
        routeRelay.handler = { [weak self] change in self?.handle(change) }

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [interruptionRelay] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            switch type {
            case .began:
                interruptionRelay.send(.began)
            case .ended:
                let rawOptions = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
                interruptionRelay.send(.ended(shouldResume: options.contains(.shouldResume)))
            @unknown default:
                break
            }
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [routeRelay] note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
            let reason = AVAudioSession.RouteChangeReason(rawValue: raw)
            routeRelay.send(reason == .oldDeviceUnavailable ? .oldDeviceUnavailable : .other)
        })
    }

    private func configure() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            sessionLog.notice(
                "session ready category=\(session.category.rawValue, privacy: .public) otherAudioPlaying=\(session.isOtherAudioPlaying, privacy: .public)"
            )
        } catch {
            let nsError = error as NSError
            sessionLog.error(
                "session setup failed domain=\(nsError.domain, privacy: .public) code=\(nsError.code) description=\(nsError.localizedDescription, privacy: .public)"
            )
        }
    }

    private func handle(_ event: AudioInterruption) {
        switch event {
        case .began:
            sessionLog.notice("interruption began")
            if player.isPlaying { Task { await player.togglePlayPause() } }
        case .ended(let shouldResume):
            sessionLog.notice("interruption ended shouldResume=\(shouldResume, privacy: .public)")
            if shouldResume, player.state == .paused { Task { await player.togglePlayPause() } }
        }
    }

    private func handle(_ change: RouteChange) {
        // Headphones unplugged: stop playing instead of switching to the speaker.
        if change == .oldDeviceUnavailable, player.isPlaying {
            Task { await player.togglePlayPause() }
        }
    }
}

enum AudioInterruption: Sendable {
    case began
    case ended(shouldResume: Bool)
}

enum RouteChange: Sendable {
    case oldDeviceUnavailable
    case other
}
#endif
