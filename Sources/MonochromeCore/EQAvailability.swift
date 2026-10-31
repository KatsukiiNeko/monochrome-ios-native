// EQAvailability.swift: where the equalizer can and cannot run.
import Foundation

public enum EQUnavailableReason: String, Equatable, Sendable {
    case hls
    case noAudioTrack
    case tapNotRunning

    public var message: String {
        switch self {
        case .hls:
            "The equalizer can't process this stream."
        case .noAudioTrack:
            "This item has no audio track to process."
        case .tapNotRunning:
            "The audio tap did not start for this item."
        }
    }
}

public enum EQAvailability: Equatable, Sendable {
    case available
    case unavailable(EQUnavailableReason)

    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    public var message: String? {
        if case .unavailable(let reason) = self { return reason.message }
        return nil
    }

    /// HLS is rejected by `AVPlayerItem.audioMix`, so it is rejected here.
    public static func resolve(
        url: URL,
        contentType: String?,
        hasAudioTrack: Bool
    ) -> EQAvailability {
        if isHLS(url: url, contentType: contentType) {
            return .unavailable(.hls)
        }
        if !hasAudioTrack {
            return .unavailable(.noAudioTrack)
        }
        return .available
    }

    public static func isHLS(url: URL, contentType: String?) -> Bool {
        if url.pathExtension.lowercased() == "m3u8" { return true }
        let type = (contentType ?? "").lowercased()
        return type.contains("mpegurl") || type.contains("m3u8")
    }
}
