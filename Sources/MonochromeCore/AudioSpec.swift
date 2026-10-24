// AudioSpec.swift: per-field audio specification, provenance and formatting.
import Foundation

/// Where a value came from. Measured values are read from the loaded asset or the
/// active output route; reported values come from catalog metadata.
public enum AudioProvenance: String, Equatable, Sendable {
    case measured
    case reported

    public var label: String { rawValue }
}

/// Where the bytes for the current item are coming from.
public enum AudioPlaybackSource: String, Equatable, Sendable {
    case stream
    case cache
    case download
    case local

    public var label: String {
        switch self {
        case .stream: "Stream"
        case .cache: "Cache"
        case .download: "Download"
        case .local: "Local file"
        }
    }
}

/// Read-only description of the active audio route.
public struct AudioOutput: Equatable, Sendable {
    public var port: AudioOutputPort
    public var sampleRateHz: Int?

    public init(port: AudioOutputPort, sampleRateHz: Int? = nil) {
        self.port = port
        self.sampleRateHz = sampleRateHz
    }
}

public enum AudioOutputPort: String, Equatable, Sendable {
    case speaker
    case headphones
    case bluetooth
    case usb
    case airPlay
    case other

    public var label: String {
        switch self {
        case .speaker: "Speaker"
        case .headphones: "Headphones"
        case .bluetooth: "Bluetooth"
        case .usb: "USB"
        case .airPlay: "AirPlay"
        case .other: "Other"
        }
    }
}

/// Everything known about the audio currently playing. Every optional is genuinely
/// unknown when nil; nothing is derived from a quality tier.
public struct AudioSpec: Equatable, Sendable {
    /// Fields that carry a provenance label in the sheet.
    public enum Field: String, CaseIterable, Sendable {
        case codec
        case container
        case sampleRate
        case bitDepth
        case channels
        case bitrate
    }

    public var codec: String?
    public var container: String?
    public var sampleRateHz: Int?
    public var bitDepth: Int?
    public var channels: Int?
    public var bitrateKbps: Int?
    /// True when the bitrate is an estimate rather than a declared average.
    public var bitrateIsEstimated = true
    public var qualityRequested: AudioQuality?
    /// Only set when the played tier is known to differ from the requested one.
    public var qualityActual: AudioQuality?
    public var source: AudioPlaybackSource
    public var output: AudioOutput?
    private var provenance: [Field: AudioProvenance]

    public init(
        codec: String? = nil,
        container: String? = nil,
        sampleRateHz: Int? = nil,
        bitDepth: Int? = nil,
        channels: Int? = nil,
        bitrateKbps: Int? = nil,
        bitrateIsEstimated: Bool = true,
        qualityRequested: AudioQuality? = nil,
        qualityActual: AudioQuality? = nil,
        source: AudioPlaybackSource,
        output: AudioOutput? = nil,
        provenance: [Field: AudioProvenance] = [:]
    ) {
        self.codec = codec
        self.container = container
        self.sampleRateHz = sampleRateHz
        self.bitDepth = bitDepth
        self.channels = channels
        self.bitrateKbps = bitrateKbps
        self.bitrateIsEstimated = bitrateIsEstimated
        self.qualityRequested = qualityRequested
        self.qualityActual = qualityActual
        self.source = source
        self.output = output
        self.provenance = provenance
    }

    /// Builds a spec from the parsed stream format. All parsed fields are measured.
    public static func from(
        format: AudioFormat?,
        quality: AudioQuality?,
        source: AudioPlaybackSource,
        output: AudioOutput? = nil
    ) -> AudioSpec {
        var provenance: [Field: AudioProvenance] = [:]
        if format?.codec.isEmpty == false { provenance[.codec] = .measured }
        if format?.sampleRateHz != nil { provenance[.sampleRate] = .measured }
        if format?.bitDepth != nil { provenance[.bitDepth] = .measured }
        if format?.channels != nil { provenance[.channels] = .measured }
        if format?.bitrateKbps != nil { provenance[.bitrate] = .measured }
        return AudioSpec(
            codec: format?.codec,
            sampleRateHz: format?.sampleRateHz,
            bitDepth: format?.bitDepth,
            channels: format?.channels,
            bitrateKbps: format?.bitrateKbps,
            bitrateIsEstimated: format?.bitrateIsEstimated ?? true,
            qualityRequested: quality,
            source: source,
            output: output,
            provenance: provenance
        )
    }

    public func provenance(for field: Field) -> AudioProvenance? {
        provenance[field]
    }

    /// A measured value overrides a reported one. Equal-provenance conflicts keep the
    /// fresher value. A disagreement is logged by field name only.
    public mutating func merge(_ incoming: AudioSpec, log: ((String) -> Void)? = nil) {
        merge(\.codec, .codec, incoming, log)
        merge(\.container, .container, incoming, log)
        merge(\.sampleRateHz, .sampleRate, incoming, log)
        merge(\.bitDepth, .bitDepth, incoming, log)
        merge(\.channels, .channels, incoming, log)
        merge(\.bitrateKbps, .bitrate, incoming, log)
        if incoming.bitrateKbps != nil {
            bitrateIsEstimated = incoming.bitrateIsEstimated
        }
        if let requested = incoming.qualityRequested { qualityRequested = requested }
        if let actual = incoming.qualityActual { qualityActual = actual }
        if let incomingOutput = incoming.output { output = incomingOutput }
    }

    private mutating func merge<T: Equatable>(
        _ target: WritableKeyPath<AudioSpec, T?>,
        _ field: Field,
        _ incoming: AudioSpec,
        _ log: ((String) -> Void)?
    ) {
        guard let newValue = incoming[keyPath: target] else { return }
        let newProvenance = incoming.provenance[field] ?? .reported
        guard let oldValue = self[keyPath: target] else {
            self[keyPath: target] = newValue
            provenance[field] = newProvenance
            return
        }
        let oldProvenance = provenance[field] ?? .reported
        if oldValue != newValue {
            log?("audiospec mismatch field=\(field.rawValue)")
        }
        if oldProvenance == .measured, newProvenance == .reported { return }
        self[keyPath: target] = newValue
        provenance[field] = newProvenance
    }
}

/// Pure display formatting; every function returns nil rather than guessing.
public enum AudioSpecFormat {
    public static func sampleRate(_ hz: Int?) -> String? {
        guard let hz, hz > 0 else { return nil }
        let kHz = Double(hz) / 1000
        let text = kHz == kHz.rounded()
            ? String(Int(kHz))
            : String(format: "%.1f", kHz)
        return "\(text) kHz"
    }

    public static func spokenSampleRate(_ hz: Int?) -> String? {
        guard let hz, hz > 0 else { return nil }
        let kHz = Double(hz) / 1000
        let text = kHz == kHz.rounded()
            ? String(Int(kHz))
            : String(format: "%.1f", kHz)
        return "\(text) kilohertz"
    }

    public static func bitDepth(_ bits: Int?) -> String? {
        guard let bits, bits > 0 else { return nil }
        return "\(bits)-bit"
    }

    public static func channels(_ count: Int?) -> String? {
        guard let count, count > 0 else { return nil }
        switch count {
        case 1: return "Mono"
        case 2: return "Stereo"
        default: return "\(count) ch"
        }
    }

    /// Estimated bitrates are rounded to the nearest 10 kbps and prefixed with "~".
    public static func bitrate(_ kbps: Int?, estimated: Bool = true) -> String? {
        guard let kbps, kbps > 0 else { return nil }
        if estimated {
            let rounded = Int((Double(kbps) / 10).rounded()) * 10
            return "~\(rounded) kbps"
        }
        return "\(kbps) kbps"
    }

    /// "FLAC · 16-bit / 44.1 kHz"; unknown parts are omitted entirely.
    public static func summary(for spec: AudioSpec) -> String? {
        var parts: [String] = []
        if let name = AudioCodecName.displayName(for: spec.codec) { parts.append(name) }
        if let detail = detail(for: spec) { parts.append(detail) }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    /// "16-bit / 44.1 kHz"; unknown parts are omitted, nil when neither is known.
    public static func detail(for spec: AudioSpec) -> String? {
        let values = [bitDepth(spec.bitDepth), sampleRate(spec.sampleRateHz)].compactMap { $0 }
        return values.isEmpty ? nil : values.joined(separator: " / ")
    }

    /// Spoken version of the summary, with the codec and sample rate expanded.
    public static func spokenSummary(for spec: AudioSpec) -> String? {
        var parts: [String] = []
        if let name = AudioCodecName.displayName(for: spec.codec) { parts.append(name) }
        if let depth = bitDepth(spec.bitDepth) { parts.append(depth) }
        if let rate = spokenSampleRate(spec.sampleRateHz) { parts.append(rate) }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// Spoken version of `detail(for:)`, using the expanded sample-rate unit.
    public static func spokenDetail(for spec: AudioSpec) -> String? {
        let values = [bitDepth(spec.bitDepth), spokenSampleRate(spec.sampleRateHz)].compactMap { $0 }
        return values.isEmpty ? nil : values.joined(separator: ", ")
    }

    /// "Lossless → High" only when a fallback actually happened.
    public static func qualityFallback(
        requested: AudioQuality?,
        actual: AudioQuality?
    ) -> String? {
        guard let requested, let actual, requested != actual else { return nil }
        return "\(requested.spokenName) → \(actual.spokenName)"
    }
}

/// FourCC names AVFoundation reports for the formats this app can receive.
public enum AudioCodecName {
    private static let names: [String: String] = [
        "flac": "FLAC",
        "alac": "ALAC",
        "aac": "AAC",
        "aac ": "AAC",
        "mp4a": "AAC",
        ".mp3": "MP3",
        "mp3": "MP3",
        "opus": "Opus",
        "lpcm": "PCM",
        "sowt": "PCM",
        "twos": "PCM",
        "ac-3": "Dolby Digital",
        "ec-3": "Dolby Digital Plus",
        "dtsc": "DTS",
    ]

    /// Returns nil for a code the app has no honest name for.
    public static func displayName(for codec: String?) -> String? {
        guard let codec else { return nil }
        let key = codec.trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty else { return nil }
        return names[key]
    }
}
