// EQRuntime.swift: the render chain the audio tap runs. Built once per
// snapshot, then only value copies and pointer walks.
import Foundation

/// An immutable set of coefficients for one sample rate. Built on the main
/// thread and handed to the audio thread.
public struct EQSnapshot: Equatable, Sendable {
    public var coefficients: [BiquadCoefficients]
    public var preampLinear: Double
    public var boostLinear: Double
    public var isLimiterEnabled: Bool
    public var stereoWidth: Double
    /// Nothing to do: the tap is not attached and the signal stays untouched.
    public var isBypass: Bool

    public init(
        coefficients: [BiquadCoefficients] = [],
        preampLinear: Double = 1,
        boostLinear: Double = 1,
        isLimiterEnabled: Bool = false,
        stereoWidth: Double = 1,
        isBypass: Bool = true
    ) {
        self.coefficients = coefficients
        self.preampLinear = preampLinear
        self.boostLinear = boostLinear
        self.isLimiterEnabled = isLimiterEnabled
        self.stereoWidth = stereoWidth
        self.isBypass = isBypass
    }

    public static func make(settings: EQSettings, sampleRate: Double) -> EQSnapshot {
        guard settings.isEnabled, !settings.isFlat else {
            return EQSnapshot()
        }
        let filters = settings.effectiveFilters
        let preampDB = settings.preampDB(sampleRate: sampleRate)
        return EQSnapshot(
            coefficients: filters.map { BiquadCoefficients(spec: $0, sampleRate: sampleRate) },
            preampLinear: pow(10, preampDB / 20),
            boostLinear: pow(10, settings.dynamicBoostDB / 20),
            isLimiterEnabled: settings.dynamicBoostDB > 0,
            stereoWidth: settings.stereoWidth,
            isBypass: false
        )
    }
}

/// A biquad cascade with a fixed number of slots. Slots past the active count
/// hold identity coefficients, so a changing filter count is a ramp from
/// identity to the new section. All storage is allocated in `init`.
public final class EQChain {
    public static let defaultCapacity = 24
    private static let identity = BiquadCoefficients(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)

    public let channelCount: Int
    public let capacity: Int

    private var coefficients: [BiquadCoefficients]
    private var targets: [BiquadCoefficients]
    private var states: [[BiquadState]]
    private var activeCount = 0
    private var targetCount = 0
    private var rampRemaining = 0

    public init(channelCount: Int, capacity: Int = EQChain.defaultCapacity) {
        let channels = max(1, channelCount)
        let slots = max(1, capacity)
        self.channelCount = channels
        self.capacity = slots
        self.coefficients = Array(repeating: Self.identity, count: slots)
        self.targets = self.coefficients
        self.states = (0..<channels).map { _ in
            Array(repeating: BiquadState(), count: slots)
        }
    }

    public var isRamping: Bool { rampRemaining > 0 }

    public func reset() {
        for channel in states.indices {
            for slot in states[channel].indices { states[channel][slot].reset() }
        }
        rampRemaining = 0
    }

    /// Points the chain at new coefficients. Filter state is kept, so the ramp
    /// changes the response without a discontinuity in the signal.
    public func setTarget(_ newCoefficients: [BiquadCoefficients], rampSamples: Int) {
        let count = min(newCoefficients.count, capacity)
        for slot in 0..<capacity {
            targets[slot] = slot < count ? newCoefficients[slot] : Self.identity
        }
        targetCount = count
        activeCount = max(activeCount, count)
        rampRemaining = max(1, rampSamples)
    }

    /// Jumps to the target coefficients and drops the ramp.
    public func applyImmediately() {
        for slot in 0..<capacity { coefficients[slot] = targets[slot] }
        activeCount = targetCount
        rampRemaining = 0
    }

    public func processInterleaved(_ samples: UnsafeMutablePointer<Float>, frameCount: Int) {
        guard frameCount > 0, activeCount > 0 else { return }
        for frame in 0..<frameCount {
            let alpha = nextAlpha()
            for channel in 0..<channelCount {
                let index = frame * channelCount + channel
                samples[index] = Float(filter(Double(samples[index]), channel: channel, alpha: alpha))
            }
            advanceRamp()
        }

    }

    public func processPlanar(
        _ channelPointers: [UnsafeMutablePointer<Float>],
        frameCount: Int
    ) {
        guard frameCount > 0, activeCount > 0 else { return }
        let channels = min(channelCount, channelPointers.count)
        for frame in 0..<frameCount {
            let alpha = nextAlpha()
            for channel in 0..<channels {
                let pointer = channelPointers[channel]
                pointer[frame] = Float(filter(Double(pointer[frame]), channel: channel, alpha: alpha))
            }
            advanceRamp()
        }
    }

    /// Pointer form for the audio thread: no array is built per buffer.
    public func processPlanar(
        _ pointers: UnsafeMutablePointer<UnsafeMutablePointer<Float>>,
        channels channelCount: Int,
        frameCount: Int
    ) {
        guard frameCount > 0, activeCount > 0, channelCount > 0 else { return }
        let channels = min(self.channelCount, channelCount)
        for frame in 0..<frameCount {
            let alpha = nextAlpha()
            for channel in 0..<channels {
                let pointer = pointers[channel]
                pointer[frame] = Float(filter(Double(pointer[frame]), channel: channel, alpha: alpha))
            }
            advanceRamp()
        }
    }

    // MARK: - Internals

    private func nextAlpha() -> Double {
        rampRemaining > 0 ? 1 / Double(rampRemaining) : 1
    }

    private func advanceRamp() {
        guard rampRemaining > 0 else { return }
        rampRemaining -= 1
        if rampRemaining == 0 { applyImmediately() }
    }

    private func filter(_ sample: Double, channel: Int, alpha: Double) -> Double {
        var value = sample
        let base = min(channel, channelCount - 1)
        if alpha >= 1 {
            for slot in 0..<activeCount {
                value = states[base][slot].process(value, coefficients[slot])
            }
        } else {
            for slot in 0..<activeCount {
                coefficients[slot].b0 += (targets[slot].b0 - coefficients[slot].b0) * alpha
                coefficients[slot].b1 += (targets[slot].b1 - coefficients[slot].b1) * alpha
                coefficients[slot].b2 += (targets[slot].b2 - coefficients[slot].b2) * alpha
                coefficients[slot].a1 += (targets[slot].a1 - coefficients[slot].a1) * alpha
                coefficients[slot].a2 += (targets[slot].a2 - coefficients[slot].a2) * alpha
                value = states[base][slot].process(value, coefficients[slot])
            }
        }
        return value
    }
}

/// The full audio-thread path: filters, preamp, Dynamic Boost make-up, limiter
/// and stereo width. Snapshots are built on the main thread; the renderer only
/// mutates its own fixed buffers.
public final class EQRenderer {
    public static let limiterCeilingDB = -1.0
    public static let releaseSeconds = 0.1

    public let channelCount: Int
    private let chain: EQChain
    private var limiters: [PeakLimiter]
    private var preamp: Double = 1
    private var preampTarget: Double = 1
    private var boost: Double = 1
    private var boostTarget: Double = 1
    private var width: Double = 1
    private var widthTarget: Double = 1
    private var rampRemaining = 0
    private var isLimiterEnabled = false
    private var isBypassed = true

    /// Largest sample seen after the preamp, before boosting and limiting.
    /// Read by the UI to light the clip indicator, then cleared.
    public private(set) var peakSinceReset: Double = 0

    public init(channelCount: Int, capacity: Int = EQChain.defaultCapacity, sampleRate: Double) {
        let channels = max(1, channelCount)
        self.channelCount = channels
        self.chain = EQChain(channelCount: channels, capacity: capacity)
        self.limiters = (0..<channels).map { _ in
            PeakLimiter(sampleRate: sampleRate, ceilingDB: Self.limiterCeilingDB)
        }
    }

    public var isBypass: Bool { isBypassed }

    public func reset() {
        chain.reset()
        for index in limiters.indices { limiters[index].reset() }
        peakSinceReset = 0
    }

    public func takePeak() -> Double {
        let value = peakSinceReset
        peakSinceReset = 0
        return value
    }

    public func update(_ snapshot: EQSnapshot, rampSamples: Int) {
        isBypassed = snapshot.isBypass
        rampRemaining = max(1, rampSamples)
        guard !snapshot.isBypass else {
            chain.setTarget([], rampSamples: rampSamples)
            preampTarget = 1
            boostTarget = 1
            widthTarget = 1
            isLimiterEnabled = false
            return
        }
        chain.setTarget(snapshot.coefficients, rampSamples: rampSamples)
        preampTarget = snapshot.preampLinear
        boostTarget = snapshot.boostLinear
        widthTarget = snapshot.stereoWidth
        isLimiterEnabled = snapshot.isLimiterEnabled
    }

    public func processInterleaved(_ samples: UnsafeMutablePointer<Float>, frameCount: Int) {
        guard frameCount > 0 else { return }
        if isBypassed {
            for frame in 0..<frameCount {
                for channel in 0..<channelCount {
                    trackPeak(abs(Double(samples[frame * channelCount + channel])))
                }
            }
            return
        }
        chain.processInterleaved(samples, frameCount: frameCount)
        for frame in 0..<frameCount {
            let alpha = nextAlpha()
            advanceGains(alpha)
            for channel in 0..<channelCount {
                let index = frame * channelCount + channel
                samples[index] = renderSample(samples[index], channel: channel)
            }
            if channelCount >= 2 {
                let base = frame * channelCount
                StereoWidth.apply(width: width, left: &samples[base], right: &samples[base + 1])
            }
            advanceRamp()
        }
        settle()
    }

    public func processPlanar(
        _ channelPointers: [UnsafeMutablePointer<Float>],
        frameCount: Int
    ) {
        channelPointers.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            processPlanar(
                UnsafeMutablePointer(mutating: base),
                channels: buffer.count,
                frameCount: frameCount
            )
        }
    }

    /// Pointer form for the audio thread: no array is built per buffer.
    public func processPlanar(
        _ pointers: UnsafeMutablePointer<UnsafeMutablePointer<Float>>,
        channels channelCount: Int,
        frameCount: Int
    ) {
        guard frameCount > 0, channelCount > 0 else { return }
        let channels = min(self.channelCount, channelCount)
        if isBypassed {
            for channel in 0..<channels {
                for frame in 0..<frameCount {
                    trackPeak(abs(Double(pointers[channel][frame])))
                }
            }
            return
        }
        chain.processPlanar(pointers, channels: channels, frameCount: frameCount)
        for frame in 0..<frameCount {
            let alpha = nextAlpha()
            advanceGains(alpha)
            for channel in 0..<channels {
                let pointer = pointers[channel]
                pointer[frame] = renderSample(pointer[frame], channel: channel)
            }
            if channels >= 2 {
                StereoWidth.apply(
                    width: width,
                    left: &pointers[0][frame],
                    right: &pointers[1][frame]
                )
            }
            advanceRamp()
        }
        settle()
    }

    // MARK: - Internals

    private func nextAlpha() -> Double {
        rampRemaining > 0 ? 1 / Double(rampRemaining) : 1
    }

    private func advanceGains(_ alpha: Double) {
        guard alpha < 1 else {
            preamp = preampTarget
            boost = boostTarget
            width = widthTarget
            return
        }
        preamp += (preampTarget - preamp) * alpha
        boost += (boostTarget - boost) * alpha
        width += (widthTarget - width) * alpha
    }

    private func advanceRamp() {
        if rampRemaining > 0 { rampRemaining -= 1 }
    }

    private func settle() {
        guard rampRemaining == 0 else { return }
        preamp = preampTarget
        boost = boostTarget
        width = widthTarget
    }

    private func renderSample(_ sample: Float, channel: Int) -> Float {
        var value = Double(sample) * preamp
        trackPeak(abs(value))
        value *= boost
        guard isLimiterEnabled else { return Float(value) }
        let index = min(max(channel, 0), limiters.count - 1)
        return limiters[index].process(Float(value))
    }

    private func trackPeak(_ magnitude: Double) {
        if magnitude > peakSinceReset { peakSinceReset = magnitude }
    }
}
