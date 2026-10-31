// EQDynamics.swift: limiter, stereo width and coefficient smoothing.
import Foundation

/// Peak limiter with instantaneous attack and an exponential release.
/// Used as the make-up stage for Dynamic Boost and as the final safety net.
public struct PeakLimiter: Sendable {
    public let ceilingDB: Double
    public let makeupDB: Double
    public let releaseSeconds: Double
    private let ceiling: Double
    private let makeup: Double
    private let releaseCoefficient: Double
    private var gain: Double

    public init(
        sampleRate: Double,
        ceilingDB: Double = -1,
        makeupDB: Double = 0,
        releaseSeconds: Double = 0.1
    ) {
        let fs = max(sampleRate, 1)
        self.ceilingDB = ceilingDB
        self.makeupDB = makeupDB
        self.releaseSeconds = releaseSeconds
        self.ceiling = pow(10, ceilingDB / 20)
        self.makeup = pow(10, makeupDB / 20)
        self.releaseCoefficient = exp(-1 / (max(releaseSeconds, 0.001) * fs))
        self.gain = 1
    }

    public mutating func reset() {
        gain = 1
    }

    public mutating func process(_ sample: Float) -> Float {
        let boosted = Double(sample) * makeup
        let magnitude = abs(boosted)
        if magnitude >= ceiling {
            // Instant attack: never let the gain rise while the signal is over.
            gain = min(gain, ceiling / magnitude)
        } else {
            gain = releaseCoefficient * gain + (1 - releaseCoefficient)
        }
        if abs(gain) < 1e-30 { gain = 0 }
        let limited = min(abs(boosted) * gain, ceiling)
        return Float(boosted < 0 ? -limited : limited)
    }

    public mutating func process(_ samples: UnsafeMutablePointer<Float>, count: Int) {
        for index in 0..<max(0, count) {
            samples[index] = process(samples[index])
        }
    }
}

/// Mid/side stereo width. 1 is identity, 0 collapses to mono, 2 doubles the side.
public enum StereoWidth {
    public static func apply(width: Double, left: inout Float, right: inout Float) {
        let amount = min(max(width.isFinite ? width : 1, 0), 2)
        guard amount != 1 else { return }
        let mid = (left + right) / 2
        let side = (left - right) / 2 * Float(amount)
        left = mid + side
        right = mid - side
    }

    public static func apply(
        width: Double,
        interleaved samples: UnsafeMutablePointer<Float>,
        frameCount: Int,
        channelCount: Int
    ) {
        guard channelCount >= 2 else { return }
        for frame in 0..<max(0, frameCount) {
            let base = frame * channelCount
            apply(width: width, left: &samples[base], right: &samples[base + 1])
        }
    }
}

/// Linear ramp between two coefficient sets. The tap calls `next()` once per
/// sample while the ramp runs, so a parameter change never steps.
public struct CoefficientRamp: Equatable, Sendable {
    public let from: BiquadCoefficients
    public let to: BiquadCoefficients
    public let length: Int
    public private(set) var position: Int

    public init(from: BiquadCoefficients, to: BiquadCoefficients, length: Int) {
        self.from = from
        self.to = to
        self.length = max(1, length)
        self.position = 0
    }

    public var isFinished: Bool { position >= length }

    public mutating func next() -> BiquadCoefficients {
        guard position < length else { return to }
        let progress = Double(position) / Double(length)
        position += 1
        return BiquadCoefficients(
            b0: from.b0 + (to.b0 - from.b0) * progress,
            b1: from.b1 + (to.b1 - from.b1) * progress,
            b2: from.b2 + (to.b2 - from.b2) * progress,
            a1: from.a1 + (to.a1 - from.a1) * progress,
            a2: from.a2 + (to.a2 - from.a2) * progress
        )
    }
}
