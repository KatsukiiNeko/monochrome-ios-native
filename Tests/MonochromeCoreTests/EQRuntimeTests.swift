// EQRuntimeTests.swift: the render chain the tap runs, on the host.
import Foundation
import Testing
@testable import MonochromeCore

private func sine(frequency: Double, sampleRate: Double, frames: Int) -> [Float] {
    (0..<frames).map { index in
        Float(0.25 * sin(2 * Double.pi * frequency * Double(index) / sampleRate))
    }
}

private func rms(_ samples: [Float]) -> Double {
    guard !samples.isEmpty else { return 0 }
    let sum = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
    return sqrt(sum / Double(samples.count))
}

private func settings(enabled: Bool = true, peakGain: Double = 6) -> EQSettings {
    var settings = EQSettings(isEnabled: enabled, mode: .parametric)
    settings.filters = [FilterSpec(kind: .peak, frequency: 1_000, gainDB: peakGain, q: 1)]
    return settings
}

@Test func disabledSettingsProduceABypassSnapshot() {
    let snapshot = EQSnapshot.make(settings: settings(enabled: false), sampleRate: 48_000)
    #expect(snapshot.isBypass)
    #expect(snapshot.coefficients.isEmpty)
}

@Test func flatSettingsProduceABypassSnapshot() {
    let snapshot = EQSnapshot.make(settings: EQSettings(isEnabled: true), sampleRate: 48_000)
    #expect(snapshot.isBypass)
}

@Test func snapshotCarriesThePreampAndBoost() {
    var source = settings()
    source.dynamicBoostDB = 3
    source.stereoWidth = 1.5
    let snapshot = EQSnapshot.make(settings: source, sampleRate: 48_000)
    #expect(!snapshot.isBypass)
    #expect(snapshot.coefficients.count == 1)
    #expect(abs(snapshot.boostLinear - pow(10, 3.0 / 20)) < 1e-12)
    #expect(snapshot.isLimiterEnabled)
    #expect(snapshot.stereoWidth == 1.5)
    // +6 dB of boost needs about 6 dB of headroom.
    #expect(abs(snapshot.preampLinear - pow(10, -6.0 / 20)) < 0.02)
}

@Test func rendererAppliesTheFilterGain() {
    var source = settings()
    source.autoPreamp = false
    var samples = sine(frequency: 1_000, sampleRate: 48_000, frames: 48_000)
    let inputTail = Array(samples.suffix(4_800))
    let renderer = EQRenderer(channelCount: 1, sampleRate: 48_000)
    renderer.update(EQSnapshot.make(settings: source, sampleRate: 48_000), rampSamples: 1)
    samples.withUnsafeMutableBufferPointer { buffer in
        renderer.processPlanar([buffer.baseAddress!], frameCount: buffer.count)
    }
    let gainDB = 20 * log10(rms(Array(samples.suffix(4_800))) / rms(inputTail))
    #expect(abs(gainDB - 6) < 0.3, "measured \(gainDB) dB")
}

@Test func autoPreampKeepsTheBoostedPeakAtUnity() {
    var samples = sine(frequency: 1_000, sampleRate: 48_000, frames: 48_000)
    let inputTail = Array(samples.suffix(4_800))
    let renderer = EQRenderer(channelCount: 1, sampleRate: 48_000)
    renderer.update(EQSnapshot.make(settings: settings(), sampleRate: 48_000), rampSamples: 1)
    samples.withUnsafeMutableBufferPointer { buffer in
        renderer.processPlanar([buffer.baseAddress!], frameCount: buffer.count)
    }
    let gainDB = 20 * log10(rms(Array(samples.suffix(4_800))) / rms(inputTail))
    #expect(abs(gainDB) < 0.1, "measured \(gainDB) dB")
}

@Test func bypassRendererReturnsTheInput() {
    let renderer = EQRenderer(channelCount: 2, sampleRate: 48_000)
    renderer.update(EQSnapshot(), rampSamples: 1)
    var samples = sine(frequency: 440, sampleRate: 48_000, frames: 4_096)
    let input = samples
    let frames = samples.count / 2
    samples.withUnsafeMutableBufferPointer { buffer in
        renderer.processInterleaved(buffer.baseAddress!, frameCount: frames)
    }
    for (left, right) in zip(samples, input) where left != right {
        Issue.record("bypass changed a sample")
        break
    }
}

@Test func blockSizeDoesNotChangeTheRenderedOutput() {
    let snapshot = EQSnapshot.make(settings: settings(), sampleRate: 48_000)

    func run(chunk: Int) -> [Float] {
        let renderer = EQRenderer(channelCount: 1, sampleRate: 48_000)
        renderer.update(snapshot, rampSamples: 1)
        var samples = sine(frequency: 1_000, sampleRate: 48_000, frames: 8_192)
        samples.withUnsafeMutableBufferPointer { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = min(chunk, buffer.count - offset)
                let pointer = buffer.baseAddress!.advanced(by: offset)
                renderer.processPlanar([pointer], frameCount: count)
                offset += count
            }
        }
        return samples
    }

    let small = run(chunk: 64)
    let large = run(chunk: 4_096)
    for (left, right) in zip(small, large) {
        #expect(abs(left - right) < 1e-5)
    }
}

@Test func parameterChangeDoesNotStepTheSignal() {
    let renderer = EQRenderer(channelCount: 1, sampleRate: 48_000)
    renderer.update(EQSnapshot.make(settings: settings(peakGain: 12), sampleRate: 48_000), rampSamples: 1)
    var samples = sine(frequency: 1_000, sampleRate: 48_000, frames: 4_800)
    samples.withUnsafeMutableBufferPointer { buffer in
        // Settle on +12 dB, then ramp to -12 dB in the middle of the buffer.
        renderer.processPlanar([buffer.baseAddress!], frameCount: 2_400)
        renderer.update(EQSnapshot.make(settings: settings(peakGain: -12), sampleRate: 48_000), rampSamples: 512)
        let tail = buffer.baseAddress!.advanced(by: 2_400)
        renderer.processPlanar([tail], frameCount: 2_400)
    }
    let largestStep = (1..<samples.count).reduce(0.0) { worst, index in
        max(worst, abs(Double(samples[index] - samples[index - 1])))
    }
    // A 1 kHz sine at 0.25 amplitude moves at most 0.033 per sample; a step
    // from swapping coefficients outright would be an order larger.
    #expect(largestStep < 0.1, "largest sample step \(largestStep)")
}

@Test func planarAndInterleavedAgree() {
    let snapshot = EQSnapshot.make(settings: settings(), sampleRate: 48_000)
    let frames = 2_048
    let left = sine(frequency: 1_000, sampleRate: 48_000, frames: frames)
    let right = sine(frequency: 500, sampleRate: 48_000, frames: frames)

    var interleaved = [Float](repeating: 0, count: frames * 2)
    for frame in 0..<frames {
        interleaved[frame * 2] = left[frame]
        interleaved[frame * 2 + 1] = right[frame]
    }
    let interleavedRenderer = EQRenderer(channelCount: 2, sampleRate: 48_000)
    interleavedRenderer.update(snapshot, rampSamples: 1)
    interleaved.withUnsafeMutableBufferPointer { buffer in
        interleavedRenderer.processInterleaved(buffer.baseAddress!, frameCount: frames)
    }

    var planarLeft = left
    var planarRight = right
    let planarRenderer = EQRenderer(channelCount: 2, sampleRate: 48_000)
    planarRenderer.update(snapshot, rampSamples: 1)
    planarLeft.withUnsafeMutableBufferPointer { leftBuffer in
        planarRight.withUnsafeMutableBufferPointer { rightBuffer in
            planarRenderer.processPlanar([leftBuffer.baseAddress!, rightBuffer.baseAddress!], frameCount: frames)
        }
    }

    for frame in 0..<frames {
        #expect(abs(interleaved[frame * 2] - planarLeft[frame]) < 1e-5)
        #expect(abs(interleaved[frame * 2 + 1] - planarRight[frame]) < 1e-5)
    }
}

@Test func dynamicBoostHoldsTheCeilingAndReportsPeaks() {
    var source = settings(peakGain: 12)
    source.dynamicBoostDB = 6
    let renderer = EQRenderer(channelCount: 1, sampleRate: 48_000)
    renderer.update(EQSnapshot.make(settings: source, sampleRate: 48_000), rampSamples: 1)
    var samples = sine(frequency: 1_000, sampleRate: 48_000, frames: 48_000)
    samples.withUnsafeMutableBufferPointer { buffer in
        renderer.processPlanar([buffer.baseAddress!], frameCount: buffer.count)
    }
    let ceiling = pow(10.0, EQRenderer.limiterCeilingDB / 20)
    let loudest = samples.reduce(0.0) { max($0, abs(Double($1))) }
    #expect(loudest <= ceiling + 1e-4, "peak \(loudest) vs ceiling \(ceiling)")
    #expect(renderer.takePeak() > 0)
    #expect(renderer.takePeak() == 0)
}

@Test func stereoWidthCollapsesTheSideChannel() {
    var source = settings(peakGain: 0.0001)
    source.stereoWidth = 0
    let renderer = EQRenderer(channelCount: 2, sampleRate: 48_000)
    renderer.update(EQSnapshot.make(settings: source, sampleRate: 48_000), rampSamples: 1)
    var samples: [Float] = []
    for frame in 0..<1_024 {
        samples.append(Float(0.4 * sin(Double(frame) * 0.1)))
        samples.append(Float(0.1 * sin(Double(frame) * 0.1)))
    }
    let frames = samples.count / 2
    samples.withUnsafeMutableBufferPointer { buffer in
        renderer.processInterleaved(buffer.baseAddress!, frameCount: frames)
    }
    for frame in 0..<frames {
        #expect(abs(samples[frame * 2] - samples[frame * 2 + 1]) < 1e-6)
    }
}
