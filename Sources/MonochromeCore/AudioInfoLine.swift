// AudioInfoLine.swift: ordered chip variants for the Now Playing audio summary.
import Foundation

/// One piece of the audio summary. `kind` decides how the view renders it.
public struct AudioInfoChip: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case format
        case detail
        case status
    }

    public var kind: Kind
    public var text: String
    public var spokenText: String

    public init(kind: Kind, text: String, spokenText: String) {
        self.kind = kind
        self.text = text
        self.spokenText = spokenText
    }
}

public enum AudioInfoLine {
    /// Variants ordered from most to least detailed. Each one is a prefix of the
    /// full list, so a view can drop detail instead of truncating or wrapping.
    /// Unknown parts are omitted; a spec with nothing honest to show yields none.
    public static func variants(
        spec: AudioSpec,
        source: AudioPlaybackSource,
        isDownloaded: Bool
    ) -> [[AudioInfoChip]] {
        var chips: [AudioInfoChip] = []

        let format = AudioFormat(
            codec: spec.codec ?? "",
            bitDepth: spec.bitDepth,
            sampleRateHz: spec.sampleRateHz,
            channels: spec.channels,
            bitrateKbps: spec.bitrateKbps,
            bitrateIsEstimated: spec.bitrateIsEstimated
        )
        let parsedFormat = format.codec.isEmpty ? nil : format
        if let text = AudioBadge.text(format: parsedFormat, quality: spec.qualityRequested) {
            chips.append(AudioInfoChip(
                kind: .format,
                text: text,
                spokenText: AudioBadge.accessibilityLabel(
                    format: parsedFormat,
                    quality: spec.qualityRequested
                ) ?? text
            ))
        }

        if let detail = AudioSpecFormat.detail(for: spec) {
            chips.append(AudioInfoChip(
                kind: .detail,
                text: detail,
                spokenText: AudioSpecFormat.spokenDetail(for: spec) ?? detail
            ))
        }

        if let status = status(source: source, isDownloaded: isDownloaded) {
            chips.append(AudioInfoChip(
                kind: .status,
                text: status.text,
                spokenText: status.spoken
            ))
        }

        guard !chips.isEmpty else { return [] }
        return (1...chips.count).reversed().map { Array(chips.prefix($0)) }
    }

    private static func status(
        source: AudioPlaybackSource,
        isDownloaded: Bool
    ) -> (text: String, spoken: String)? {
        if isDownloaded || source == .download {
            return ("Downloaded", "Playing from a permanent download")
        }
        if source == .cache {
            return ("Cached", "Playing from the local cache")
        }
        return nil
    }
}
