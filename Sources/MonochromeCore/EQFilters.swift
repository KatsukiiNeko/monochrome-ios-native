// EQFilters.swift: biquad filters from the audio EQ cookbook, typed and pure.
import Foundation

/// The biquad shapes the equalizer can build.
public enum BiquadKind: String, Codable, CaseIterable, Sendable {
    case peak
    case lowShelf
    case highShelf
    case highPass
    case lowPass
    case notch

    /// Only peaking and shelving filters use a gain.
    public var usesGain: Bool {
        switch self {
        case .peak, .lowShelf, .highShelf: true
        case .highPass, .lowPass, .notch: false
        }
    }

    /// Default Q for the band editors.
    public var defaultQ: Double {
        switch self {
        case .peak: 1.0
        case .lowShelf, .highShelf: 0.7071
        case .highPass, .lowPass, .notch: 0.7071
        }
    }
}

/// One user-editable band. Values are clamped on construction so a decoded or
/// imported file can never put the DSP out of range.
public struct FilterSpec: Identifiable, Codable, Equatable, Hashable, Sendable {
    public static let minFrequency = 20.0
    public static let maxFrequency = 20_000.0
    public static let minGainDB = -15.0
    public static let maxGainDB = 15.0
    public static let minQ = 0.1
    public static let maxQ = 10.0

    public var id: UUID
    public var kind: BiquadKind
    public var frequency: Double
    public var gainDB: Double
    public var q: Double
    public var enabled: Bool

    public init(
        id: UUID = UUID(),
        kind: BiquadKind,
        frequency: Double,
        gainDB: Double = 0,
        q: Double? = nil,
        enabled: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.frequency = Self.clamp(frequency, Self.minFrequency...Self.maxFrequency)
        self.gainDB = kind.usesGain
            ? Self.clamp(gainDB, Self.minGainDB...Self.maxGainDB)
            : 0
        self.q = Self.clamp(q ?? kind.defaultQ, Self.minQ...Self.maxQ)
        self.enabled = enabled
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, frequency, gainDB, q, enabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decodeIfPresent(BiquadKind.self, forKey: .kind) ?? .peak
        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            kind: kind,
            frequency: try container.decodeIfPresent(Double.self, forKey: .frequency) ?? 1_000,
            gainDB: try container.decodeIfPresent(Double.self, forKey: .gainDB) ?? 0,
            q: try container.decodeIfPresent(Double.self, forKey: .q) ?? kind.defaultQ,
            enabled: try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        )
    }

    /// The band this filter belongs to for the frequency hint in the UI.
    public var rangeName: String {
        EQRanges.name(for: frequency)
    }

    static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        if value.isNaN { return range.lowerBound }
        if value.isInfinite { return value > 0 ? range.upperBound : range.lowerBound }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

/// Normalized coefficients (`a0 = 1`) for one biquad section.
public struct BiquadCoefficients: Equatable, Sendable {
    public var b0: Double
    public var b1: Double
    public var b2: Double
    public var a1: Double
    public var a2: Double

    public init(b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) {
        self.b0 = b0
        self.b1 = b1
        self.b2 = b2
        self.a1 = a1
        self.a2 = a2
    }

    /// Cookbook formulas (research §3). A frequency above `0.45 × sampleRate`
    /// is clamped so a band can never fold over Nyquist.
    public init(spec: FilterSpec, sampleRate: Double) {
        let fs = sampleRate > 0 ? sampleRate : 48_000
        let f0 = min(spec.frequency, fs * 0.45)
        let w0 = 2 * Double.pi * f0 / fs
        let cw = cos(w0)
        let sw = sin(w0)
        let q = max(spec.q, FilterSpec.minQ)
        let alpha = sw / (2 * q)
        let a = pow(10, spec.gainDB / 40)

        var b0 = 1.0
        var b1 = 0.0
        var b2 = 0.0
        var a0 = 1.0
        var a1 = 0.0
        var a2 = 0.0

        switch spec.kind {
        case .lowPass:
            b0 = (1 - cw) / 2
            b1 = 1 - cw
            b2 = (1 - cw) / 2
            a0 = 1 + alpha
            a1 = -2 * cw
            a2 = 1 - alpha
        case .highPass:
            b0 = (1 + cw) / 2
            b1 = -(1 + cw)
            b2 = (1 + cw) / 2
            a0 = 1 + alpha
            a1 = -2 * cw
            a2 = 1 - alpha
        case .notch:
            b0 = 1
            b1 = -2 * cw
            b2 = 1
            a0 = 1 + alpha
            a1 = -2 * cw
            a2 = 1 - alpha
        case .peak:
            b0 = 1 + alpha * a
            b1 = -2 * cw
            b2 = 1 - alpha * a
            a0 = 1 + alpha / a
            a1 = -2 * cw
            a2 = 1 - alpha / a
        case .lowShelf:
            let t = 2 * sqrt(a) * alpha
            b0 = a * ((a + 1) - (a - 1) * cw + t)
            b1 = 2 * a * ((a - 1) - (a + 1) * cw)
            b2 = a * ((a + 1) - (a - 1) * cw - t)
            a0 = (a + 1) + (a - 1) * cw + t
            a1 = -2 * ((a - 1) + (a + 1) * cw)
            a2 = (a + 1) + (a - 1) * cw - t
        case .highShelf:
            let t = 2 * sqrt(a) * alpha
            b0 = a * ((a + 1) + (a - 1) * cw + t)
            b1 = -2 * a * ((a - 1) + (a + 1) * cw)
            b2 = a * ((a + 1) + (a - 1) * cw - t)
            a0 = (a + 1) - (a - 1) * cw + t
            a1 = 2 * ((a - 1) - (a + 1) * cw)
            a2 = (a + 1) - (a - 1) * cw - t
        }

        self.b0 = b0 / a0
        self.b1 = b1 / a0
        self.b2 = b2 / a0
        self.a1 = a1 / a0
        self.a2 = a2 / a0
    }

    /// Magnitude response in dB at one frequency.
    public func magnitudeDB(at frequency: Double, sampleRate: Double) -> Double {
        let fs = sampleRate > 0 ? sampleRate : 48_000
        let f = min(max(frequency, 0.0001), fs / 2)
        let w = 2 * Double.pi * f / fs
        let c1 = cos(w)
        let s1 = sin(w)
        let c2 = cos(2 * w)
        let s2 = sin(2 * w)

        let numeratorReal = b0 + b1 * c1 + b2 * c2
        let numeratorImaginary = -(b1 * s1 + b2 * s2)
        let denominatorReal = 1 + a1 * c1 + a2 * c2
        let denominatorImaginary = -(a1 * s1 + a2 * s2)

        let numerator = hypot(numeratorReal, numeratorImaginary)
        let denominator = hypot(denominatorReal, denominatorImaginary)
        guard denominator > 0 else { return 0 }
        return 20 * log10(max(numerator / denominator, 1e-12))
    }

    /// Stable when both poles sit inside the unit circle after normalization.
    public var isStable: Bool {
        abs(a2) < 1 && abs(a1) < 1 + a2
    }
}

/// Direct Form II transposed state for one biquad. Values that decay into the
/// denormal range are flushed so silence cannot cost CPU on the audio thread.
public struct BiquadState: Sendable {
    public var z1: Double = 0
    public var z2: Double = 0

    public init() {}

    public mutating func reset() {
        z1 = 0
        z2 = 0
    }

    public mutating func process(_ sample: Double, _ c: BiquadCoefficients) -> Double {
        let output = c.b0 * sample + z1
        z1 = c.b1 * sample - c.a1 * output + z2
        z2 = c.b2 * sample - c.a2 * output
        if abs(z1) < 1e-30 { z1 = 0 }
        if abs(z2) < 1e-30 { z2 = 0 }
        return output
    }
}

/// One cascade for one channel. Coefficients are fixed for the life of the
/// instance; a parameter change builds a new processor and crossfades at the tap.
public struct ChannelEQ: Sendable {
    public private(set) var coefficients: [BiquadCoefficients]
    private var states: [BiquadState]

    public init(coefficients: [BiquadCoefficients]) {
        self.coefficients = coefficients
        self.states = Array(repeating: BiquadState(), count: coefficients.count)
    }

    public mutating func reset() {
        for index in states.indices { states[index].reset() }
    }

    public mutating func process(_ sample: Float) -> Float {
        var value = Double(sample)
        for index in coefficients.indices {
            value = states[index].process(value, coefficients[index])
        }
        return Float(value)
    }

    /// In-place processing; no allocation per call.
    public mutating func process(_ samples: UnsafeMutablePointer<Float>, count: Int) {
        guard count > 0, !coefficients.isEmpty else { return }
        for frame in 0..<count {
            var value = Double(samples[frame])
            for index in coefficients.indices {
                value = states[index].process(value, coefficients[index])
            }
            samples[frame] = Float(value)
        }
    }
}

/// A cascade per channel. Interleaved and planar layouts both write in place.
public struct EQProcessor: Sendable {
    public private(set) var channelCount: Int
    private var channels: [ChannelEQ]

    public init(coefficients: [BiquadCoefficients], channelCount: Int) {
        let count = max(1, channelCount)
        self.channelCount = count
        self.channels = (0..<count).map { _ in ChannelEQ(coefficients: coefficients) }
    }

    public mutating func reset() {
        for index in channels.indices { channels[index].reset() }
    }

    public mutating func processInterleaved(
        _ samples: UnsafeMutablePointer<Float>,
        frameCount: Int
    ) {
        guard frameCount > 0 else { return }
        for frame in 0..<frameCount {
            let base = frame * channelCount
            for channel in 0..<channelCount {
                samples[base + channel] = channels[channel].process(samples[base + channel])
            }
        }
    }

    public mutating func processPlanar(
        _ channels: [UnsafeMutablePointer<Float>],
        frameCount: Int
    ) {
        for channel in 0..<min(channelCount, channels.count) {
            self.channels[channel].process(channels[channel], count: frameCount)
        }
    }
}

/// Human names for frequency ranges, used by the parametric editor.
public enum EQRanges {
    public static func name(for frequency: Double) -> String {
        switch frequency {
        case ..<60: "Sub-bass"
        case ..<250: "Bass"
        case ..<500: "Low mids"
        case ..<2_000: "Mids"
        case ..<5_000: "Upper mids"
        case ..<8_000: "Brilliance"
        default: "Air"
        }
    }

    public static func hint(for frequency: Double) -> String {
        switch frequency {
        case ..<60: "weight, rumble"
        case ..<250: "warmth, fullness"
        case ..<500: "body, mud"
        case ..<2_000: "vocal body, snap"
        case ..<5_000: "presence, harshness"
        case ..<8_000: "detail, sibilance"
        default: "sparkle, hiss"
        }
    }
}
