// EQFilterTests.swift: golden vectors and processing properties for the core DSP.
import Foundation
import Testing
@testable import MonochromeCore

private let isoCenters: [Double] = [63, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]

private func coefficients(
    _ kind: BiquadKind,
    _ frequency: Double,
    _ gainDB: Double = 0,
    _ q: Double = 0.7071,
    sampleRate: Double = 48_000
) -> BiquadCoefficients {
    BiquadCoefficients(
        spec: FilterSpec(kind: kind, frequency: frequency, gainDB: gainDB, q: q),
        sampleRate: sampleRate
    )
}

private func expectCoefficients(
    _ actual: BiquadCoefficients,
    _ expected: [Double],
    tolerance: Double = 1e-9
) {
    #expect(abs(actual.b0 - expected[0]) < tolerance)
    #expect(abs(actual.b1 - expected[1]) < tolerance)
    #expect(abs(actual.b2 - expected[2]) < tolerance)
    #expect(abs(actual.a1 - expected[3]) < tolerance)
    #expect(abs(actual.a2 - expected[4]) < tolerance)
}

private func expectMagnitudes(
    _ actual: BiquadCoefficients,
    _ expected: [Double],
    sampleRate: Double = 48_000,
    tolerance: Double = 0.01
) {
    for (index, gain) in expected.enumerated() {
        let measured = actual.magnitudeDB(at: isoCenters[index], sampleRate: sampleRate)
        if gain == -200 {
            #expect(measured < -100, "\(isoCenters[index]) Hz: \(measured) dB")
        } else {
            #expect(abs(measured - gain) < tolerance, "\(isoCenters[index]) Hz: \(measured) dB")
        }
    }
}

// MARK: - Cookbook golden vectors

@Test func goldenVectorsAt48k() {
    let peak = coefficients(.peak, 1_000, 6, 1)
    expectCoefficients(
        peak,
        [1.0439530870, -1.8953207239, 0.8677222848, -1.8953207239, 0.9116753718]
    )
    expectMagnitudes(peak, [0.026, 0.102, 0.423, 1.879, 6.000, 1.866, 0.405, 0.084, 0.009])

    let cut = coefficients(.peak, 100, -4, 2)
    expectCoefficients(
        cut,
        [0.9984858904, -1.9916237506, 0.9933085020, -1.9916237506, 0.9917943924]
    )
    expectMagnitudes(cut, [-0.871, -2.206, -0.221, -0.044, -0.011, -0.003, -0.001, 0.000, 0.000])

    let lowShelf = coefficients(.lowShelf, 105, 4, 0.7071)
    expectCoefficients(
        lowShelf,
        [1.0022452513, -1.9826329111, 0.9806234402, -1.9826764176, 0.9828251850]
    )
    expectMagnitudes(lowShelf, [3.530, 1.340, 0.125, 0.008, 0.001, 0.000, 0.000, 0.000, 0.000])

    let highShelf = coefficients(.highShelf, 8_000, 6, 0.7071)
    expectCoefficients(
        highShelf,
        [1.5716695819, -1.2488751659, 0.4486846379, -0.4335084890, 0.2049875429]
    )
    expectMagnitudes(highShelf, [0.000, 0.000, 0.000, 0.000, 0.001, 0.017, 0.285, 3.000, 5.921])

    let highPass = coefficients(.highPass, 80, 0, 0.7071)
    expectCoefficients(
        highPass,
        [0.9926224728, -1.9852449456, 0.9926224728, -1.9851905180, 0.9852993732]
    )
    expectMagnitudes(highPass, [-5.563, -0.674, -0.045, -0.003, 0.000, 0.000, 0.000, 0.000, 0.000])

    let notch = coefficients(.notch, 1_000, 0, 4)
    expectCoefficients(
        notch,
        [0.9839461568, -1.9510567222, 0.9839461568, -1.9510567222, 0.9678923137]
    )
    expectMagnitudes(notch, [-0.001, -0.004, -0.019, -0.119, -200.000, -0.117, -0.018, -0.004, 0.000])
    #expect(notch.magnitudeDB(at: 1_000, sampleRate: 48_000) < -100)
}

@Test func goldenVectorsAt44k() {
    let peak = coefficients(.peak, 1_000, 6, 1, sampleRate: 44_100)
    expectCoefficients(
        peak,
        [1.0476300262, -1.8849912525, 0.8566564609, -1.8849912525, 0.9042864871]
    )
    expectMagnitudes(peak, [0.026, 0.102, 0.423, 1.879, 6.000, 1.863, 0.402, 0.081, 0.007], sampleRate: 44_100)

    let cut = coefficients(.peak, 100, -4, 2, sampleRate: 44_100)
    expectCoefficients(
        cut,
        [0.9983525959, -1.9908699286, 0.9927194168, -1.9908699286, 0.9910720127]
    )
    expectMagnitudes(cut, [-0.871, -2.206, -0.221, -0.044, -0.011, -0.003, -0.001, 0.000, 0.000], sampleRate: 44_100)

    let lowShelf = coefficients(.lowShelf, 105, 4, 0.7071, sampleRate: 44_100)
    expectCoefficients(
        lowShelf,
        [1.0024440391, -1.9810929718, 0.9789280475, -1.9811444745, 0.9813205840]
    )
    expectMagnitudes(lowShelf, [3.530, 1.340, 0.125, 0.008, 0.001, 0.000, 0.000, 0.000, 0.000], sampleRate: 44_100)

    let highShelf = coefficients(.highShelf, 8_000, 6, 0.7071, sampleRate: 44_100)
    expectCoefficients(
        highShelf,
        [1.5417786624, -1.0651671958, 0.3966103279, -0.3160611107, 0.1892829052]
    )
    expectMagnitudes(highShelf, [0.000, 0.000, 0.000, 0.000, 0.001, 0.016, 0.269, 3.000, 5.952], sampleRate: 44_100)

    let highPass = coefficients(.highPass, 80, 0, 0.7071, sampleRate: 44_100)
    expectCoefficients(
        highPass,
        [0.9919726637, -1.9839453275, 0.9919726637, -1.9838808895, 0.9840097654]
    )
    expectMagnitudes(highPass, [-5.563, -0.674, -0.045, -0.003, 0.000, 0.000, 0.000, 0.000, 0.000], sampleRate: 44_100)

    let notch = coefficients(.notch, 1_000, 0, 4, sampleRate: 44_100)
    expectCoefficients(
        notch,
        [0.9825602534, -1.9452088697, 0.9825602534, -1.9452088697, 0.9651205067]
    )
    expectMagnitudes(notch, [-0.001, -0.004, -0.019, -0.118, -200.000, -0.117, -0.018, -0.003, 0.000], sampleRate: 44_100)
    #expect(notch.magnitudeDB(at: 1_000, sampleRate: 44_100) < -100)
}

// MARK: - Cookbook properties

@Test func peakHasItsGainAtTheCenter() {
    for gain in [-12.0, -6, 0, 3, 6, 12] {
        let c = coefficients(.peak, 1_000, gain, 1)
        #expect(abs(c.magnitudeDB(at: 1_000, sampleRate: 48_000) - gain) < 1e-9)
    }
}

@Test func boostThenCutIsFlat() {
    for frequency in [60.0, 250, 1_000, 6_000] {
        let filters = [
            FilterSpec(kind: .peak, frequency: frequency, gainDB: 6, q: 1.2),
            FilterSpec(kind: .peak, frequency: frequency, gainDB: -6, q: 1.2),
        ]
        for test in [50.0, 125, 1_000, 4_000, 12_000] {
            #expect(abs(EQResponse.magnitudeDB(filters: filters, at: test, sampleRate: 48_000)) < 1e-9)
        }
    }
}

@Test func shelvesSitAtHalfGainAtTheirCorner() {
    let low = coefficients(.lowShelf, 200, 8, 0.7071)
    let high = coefficients(.highShelf, 4_000, -6, 0.7071)
    #expect(abs(low.magnitudeDB(at: 200, sampleRate: 48_000) - 4) < 0.1)
    #expect(abs(high.magnitudeDB(at: 4_000, sampleRate: 48_000) + 3) < 0.1)
    #expect(low.magnitudeDB(at: 20, sampleRate: 48_000) > 7)
    #expect(abs(low.magnitudeDB(at: 20_000, sampleRate: 48_000)) < 0.1)
}

@Test func highPassIsThreeDecibelsAtTheCorner() {
    let c = coefficients(.highPass, 1_000, 0, 0.7071)
    #expect(abs(c.magnitudeDB(at: 1_000, sampleRate: 48_000) + 3.0103) < 0.01)
}

@Test func everyCombinationIsStable() {
    let rates: [Double] = [44_100, 48_000, 88_200, 96_000, 192_000]
    for rate in rates {
        let highest = min(20_000, rate * 0.44)
        for frequency in [20.0, 100, 1_000, 10_000, highest] {
            for gain in [-15.0, 0, 15] {
                for q in [0.1, 1, 10] {
                    for kind in BiquadKind.allCases {
                        let c = BiquadCoefficients(
                            spec: FilterSpec(kind: kind, frequency: frequency, gainDB: gain, q: q),
                            sampleRate: rate
                        )
                        #expect(c.isStable, "\(kind) \(frequency) Hz \(gain) dB Q \(q) @ \(rate)")
                    }
                }
            }
        }
    }
}

@Test func filterSpecClampsInput() {
    let spec = FilterSpec(kind: .peak, frequency: .infinity, gainDB: 99, q: 0)
    #expect(spec.frequency == FilterSpec.maxFrequency)
    #expect(spec.gainDB == FilterSpec.maxGainDB)
    #expect(spec.q == FilterSpec.minQ)
    #expect(FilterSpec(kind: .highPass, frequency: 1_000, gainDB: 9).gainDB == 0)
}

// MARK: - Processing

private func sine(frequency: Double, sampleRate: Double, frames: Int) -> [Float] {
    (0..<frames).map { index in
        Float(sin(2 * Double.pi * frequency * Double(index) / sampleRate))
    }
}

private func rms(_ samples: [Float]) -> Double {
    guard !samples.isEmpty else { return 0 }
    let sum = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
    return sqrt(sum / Double(samples.count))
}

@Test func blockSizeDoesNotChangeTheOutput() {
    let input = sine(frequency: 1_000, sampleRate: 48_000, frames: 4_096)
    let coefficients = [coefficients(.peak, 1_000, 6, 1), coefficients(.lowShelf, 120, -3, 0.7071)]

    func run(chunk: Int) -> [Float] {
        var processor = ChannelEQ(coefficients: coefficients)
        var output = input
        output.withUnsafeMutableBufferPointer { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = min(chunk, buffer.count - offset)
                processor.process(buffer.baseAddress!.advanced(by: offset), count: count)
                offset += count
            }
        }
        return output
    }

    let small = run(chunk: 64)
    let large = run(chunk: 4_096)
    for (left, right) in zip(small, large) {
        #expect(abs(left - right) < 1e-6)
    }
}

@Test func sineSettlesAtTheFilterGain() {
    let input = sine(frequency: 1_000, sampleRate: 48_000, frames: 48_000)
    var processor = ChannelEQ(coefficients: [coefficients(.peak, 1_000, 6, 1)])
    var output = input
    output.withUnsafeMutableBufferPointer { buffer in
        processor.process(buffer.baseAddress!, count: buffer.count)
    }
    let settled = Array(output.suffix(4_800))
    let gainDB = 20 * log10(rms(settled) / rms(Array(input.suffix(4_800))))
    #expect(abs(gainDB - 6) < 0.2)
}

@Test func emptyChainIsIdentity() {
    var processor = ChannelEQ(coefficients: [])
    var output = sine(frequency: 440, sampleRate: 48_000, frames: 512)
    let input = output
    output.withUnsafeMutableBufferPointer { buffer in
        processor.process(buffer.baseAddress!, count: buffer.count)
    }
    #expect(output == input)
}

@Test func interleavedProcessorKeepsChannelsSeparate() {
    var processor = EQProcessor(coefficients: [coefficients(.peak, 1_000, 6, 1)], channelCount: 2)
    var samples = [Float](repeating: 0, count: 128)
    for frame in 0..<64 {
        samples[frame * 2] = sine(frequency: 1_000, sampleRate: 48_000, frames: 64)[frame]
        samples[frame * 2 + 1] = 0
    }
    samples.withUnsafeMutableBufferPointer { buffer in
        processor.processInterleaved(buffer.baseAddress!, frameCount: 64)
    }
    #expect(samples[1] == 0)
    #expect(samples[3] == 0)
}

// MARK: - Response and preamp

@Test func tenBandBoostPeaksAtTheKnownCompositeGain() {
    let filters = EQGraphicBands.filters(gains: Array(repeating: 6, count: 10))
    let peak = EQResponse.peakDB(filters: filters, sampleRate: 48_000)
    #expect(abs(peak - 8.83) < 0.15)
    let preamp = EQResponse.autoPreampDB(filters: filters, sampleRate: 48_000)
    #expect(preamp <= -peak)
    #expect(preamp > -peak - 0.11)
}

@Test func cutsNeedNoPreamp() {
    let filters = EQGraphicBands.filters(gains: Array(repeating: -6, count: 10))
    #expect(EQResponse.autoPreampDB(filters: filters, sampleRate: 48_000) == 0)
    #expect(EQResponse.peakDB(filters: filters, sampleRate: 48_000) < 0)
}

@Test func curveIsSampledOnALogGrid() {
    let curve = EQResponse.curve(filters: [], sampleRate: 48_000, points: 32)
    #expect(curve.count == 32)
    #expect(abs(curve.first!.frequency - 20) < 0.001)
    #expect(abs(curve.last!.frequency - 20_000) < 0.001)
    #expect(curve.allSatisfy { $0.gainDB == 0 })
}

@Test func nearestBandIndexUsesLogDistance() {
    #expect(EQGraphicBands.nearestIndex(to: 32) == 0)
    #expect(EQGraphicBands.nearestIndex(to: 1_100) == 5)
    #expect(EQGraphicBands.nearestIndex(to: 15_000) == 9)
}

// MARK: - Limiter, width and smoothing

@Test func limiterHoldsTheCeiling() {
    var limiter = PeakLimiter(sampleRate: 48_000, ceilingDB: -1, makeupDB: 6)
    let ceiling = pow(10, -1.0 / 20)
    var inputs = [Float](repeating: 1.0, count: 4_800)
    inputs[10] = 4.0
    for sample in inputs {
        let output = limiter.process(sample)
        #expect(abs(Double(output)) <= ceiling + 1e-6, "\(output) vs \(ceiling)")
        #expect(output.isFinite)
    }
}

@Test func limiterLeavesQuietSignalsAlone() {
    var limiter = PeakLimiter(sampleRate: 48_000, ceilingDB: -1, makeupDB: 0)
    for value in [Float(0), 0.1, 0.2, -0.2, 0.4] {
        let output = limiter.process(value)
        #expect(abs(output - value) < 1e-6)
    }
}

@Test func limiterSurvivesSilenceAndDenormals() {
    var limiter = PeakLimiter(sampleRate: 48_000)
    for value in [Float(0), 1e-40, -1e-40, 0] {
        let output = limiter.process(value)
        #expect(output.isFinite)
        #expect(!output.isNaN)
    }
}

@Test func widthIdentities() {
    var left: Float = 0.8
    var right: Float = 0.2
    StereoWidth.apply(width: 1, left: &left, right: &right)
    #expect(abs(left - 0.8) < 1e-6)
    #expect(abs(right - 0.2) < 1e-6)

    StereoWidth.apply(width: 0, left: &left, right: &right)
    #expect(abs(left - 0.5) < 1e-6)
    #expect(abs(right - 0.5) < 1e-6)

    var monoLeft: Float = 0.3
    var monoRight: Float = 0.3
    StereoWidth.apply(width: 2, left: &monoLeft, right: &monoRight)
    #expect(abs(monoLeft - 0.3) < 1e-6)
    #expect(abs(monoRight - 0.3) < 1e-6)
}

@Test func coefficientRampReachesItsTarget() {
    let from = coefficients(.peak, 1_000, 0, 1)
    let to = coefficients(.peak, 1_000, 9, 1)
    var ramp = CoefficientRamp(from: from, to: to, length: 64)
    var last = from
    var moved = 0
    while !ramp.isFinished {
        let next = ramp.next()
        #expect(next.b0 >= last.b0)
        last = next
        moved += 1
        #expect(moved < 1_000)
    }
    #expect(moved == 64)
    #expect(abs(last.b0 - to.b0) < abs(to.b0 - from.b0))
    #expect(ramp.next() == to)
}

@Test func rangeNamesCoverTheSpectrum() {
    #expect(EQRanges.name(for: 30) == "Sub-bass")
    #expect(EQRanges.name(for: 1_000) == "Mids")
    #expect(EQRanges.name(for: 12_000) == "Air")
    #expect(EQRanges.hint(for: 300) == "body, mud")
}
