// AudioOutputMonitor.swift: read-only view of the active audio route for the Audio sheet.
#if canImport(AVFoundation)
import AVFoundation
import MonochromeCore
import Observation

@MainActor
@Observable
final class AudioOutputMonitor {
    private(set) var output: AudioOutput?
    private let observerBox = ObserverBox()

    init() {
        refresh()
        observerBox.token = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        let session = AVAudioSession.sharedInstance()
        let rate = Int(session.sampleRate.rounded())
        output = AudioOutput(
            port: Self.port(for: session.currentRoute.outputs.first?.portType),
            sampleRateHz: rate > 0 ? rate : nil
        )
    }

    static func port(for type: AVAudioSession.Port?) -> AudioOutputPort {
        switch type {
        case .builtInSpeaker, .builtInReceiver: .speaker
        case .headphones, .headsetMic: .headphones
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE: .bluetooth
        case .usbAudio: .usb
        case .airPlay: .airPlay
        default: .other
        }
    }
}

/// The notification token outlives the main-actor object; its deinit is nonisolated.
private final class ObserverBox: @unchecked Sendable {
    var token: NSObjectProtocol?
    deinit {
        if let token { NotificationCenter.default.removeObserver(token) }
    }
}
#endif
