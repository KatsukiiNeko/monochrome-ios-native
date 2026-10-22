// AudioQuality.swift: catalog quality tiers, parsed stream format and badge wording.
import Foundation

/// Tiers the catalog reports or that a client can request.
public enum AudioQuality: String, Codable, Sendable, CaseIterable {
    case lossless = "LOSSLESS"
    case hiResLossless = "HI_RES_LOSSLESS"
    case high = "HIGH"
    case low = "LOW"
    case dolbyAtmos = "DOLBY_ATMOS"

    /// Spoken form for VoiceOver, e.g. "Lossless, FLAC".
    public var spokenName: String {
        switch self {
        case .lossless: "Lossless"
        case .hiResLossless: "High-resolution lossless"
        case .high: "High"
        case .low: "Low"
        case .dolbyAtmos: "Dolby Atmos"
        }
    }
}

/// What the player actually parsed from the stream, as reported by AVFoundation.
public struct AudioFormat: Equatable, Sendable, Codable {
    /// FourCC or MIME subtype, e.g. `flac`, `aac `, `alac`, `.mp3`.
    public var codec: String
    public var bitDepth: Int?
    public var sampleRateHz: Int?

    public init(codec: String, bitDepth: Int? = nil, sampleRateHz: Int? = nil) {
        self.codec = codec
        self.bitDepth = bitDepth
        self.sampleRateHz = sampleRateHz
    }

    /// Lowercase, punctuation-free family name used for matching.
    public var codecFamily: String {
        codec.lowercased()
            .replacingOccurrences(of: ".", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}

/// Badge text for a purchased file or a stream. Wording follows the web app so a
/// track reads the same in both clients: FLAC, HD FLAC, FLAC 16/44.1, AAC, MP3.
public enum AudioBadge {
    public static func text(format: AudioFormat? = nil, quality: AudioQuality? = nil) -> String? {
        if let format, let text = text(for: format) {
            return text
        }
        return qualityText(quality)
    }

    /// VoiceOver reads the tier before the codec, e.g. "Lossless, FLAC 16/44.1".
    public static func accessibilityLabel(format: AudioFormat? = nil, quality: AudioQuality? = nil) -> String? {
        guard let badge = text(format: format, quality: quality) else { return nil }
        guard let spoken = quality?.spokenName else { return badge }
        return "\(spoken), \(badge)"
    }

    private static func qualityText(_ quality: AudioQuality?) -> String? {
        switch quality {
        case .lossless: "FLAC"
        case .hiResLossless: "HD FLAC"
        case .high, .low: "AAC"
        case .dolbyAtmos: "Atmos"
        case nil: nil
        }
    }

    private static func text(for format: AudioFormat) -> String? {
        let family = format.codecFamily
        guard !family.isEmpty else { return nil }
        if family.contains("flac") || family.contains("alac") {
            if let depth = format.bitDepth, depth > 0,
               let rate = format.sampleRateHz, rate > 0 {
                let isHiRes = depth > 16 || rate > 48_000
                return "\(isHiRes ? "HD" : "FLAC") \(depth)/\(sampleRateLabel(rate))"
            }
            return "FLAC"
        }
        if family.contains("aac") || family.contains("mp4a") { return "AAC" }
        if family.contains("mp3") { return "MP3" }
        if family.contains("opus") { return "Opus" }
        return family.uppercased()
    }

    /// Whole kilohertz stay whole (48000 → 48), fractional ones keep a decimal (44100 → 44.1).
    private static func sampleRateLabel(_ hz: Int) -> String {
        let kHz = Double(hz) / 1000
        return kHz == kHz.rounded() ? String(Int(kHz)) : String(format: "%.1f", kHz)
    }
}
