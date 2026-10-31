// EQResponse.swift: composite response, graphic bands and automatic preamp.
import Foundation

/// One sampled point of the UI curve.
public struct EQCurvePoint: Equatable, Sendable {
    public var frequency: Double
    public var gainDB: Double

    public init(frequency: Double, gainDB: Double) {
        self.frequency = frequency
        self.gainDB = gainDB
    }
}

/// The ten ISO octave centers used by the graphic equalizer.
public enum EQGraphicBands {
    public static let frequencies: [Double] = [
        31.5, 63, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000,
    ]
    public static let q = 1.414
    public static let minGainDB = -12.0
    public static let maxGainDB = 12.0

    /// Builds one peaking filter per band; a zero-gain band is omitted so a
    /// flat graphic curve leaves the signal untouched.
    public static func filters(gains: [Double]) -> [FilterSpec] {
        frequencies.enumerated().compactMap { index, frequency in
            let gain = index < gains.count
                ? min(max(gains[index].isFinite ? gains[index] : 0, minGainDB), maxGainDB)
                : 0
            guard gain != 0 else { return nil }
            return FilterSpec(kind: .peak, frequency: frequency, gainDB: gain, q: q)
        }
    }

    /// The band index nearest to a frequency, for selecting a handle.
    public static func nearestIndex(to frequency: Double) -> Int {
        var best = 0
        var bestDistance = Double.infinity
        for (index, center) in frequencies.enumerated() {
            let distance = abs(log(max(frequency, 1) / center))
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return best
    }
}

/// Composite magnitude, curve sampling and automatic headroom.
public enum EQResponse {
    public static let defaultMinimumFrequency = 20.0
    public static let defaultMaximumFrequency = 20_000.0

    /// Sum of the enabled filters, in dB.
    public static func magnitudeDB(
        filters: [FilterSpec],
        at frequency: Double,
        sampleRate: Double
    ) -> Double {
        filters.reduce(0) { total, spec in
            guard spec.enabled else { return total }
            return total + BiquadCoefficients(spec: spec, sampleRate: sampleRate)
                .magnitudeDB(at: frequency, sampleRate: sampleRate)
        }
    }

    public static func curve(
        filters: [FilterSpec],
        sampleRate: Double,
        points: Int = 128,
        minimumFrequency: Double = defaultMinimumFrequency,
        maximumFrequency: Double = defaultMaximumFrequency
    ) -> [EQCurvePoint] {
        let count = max(2, points)
        let low = log10(max(minimumFrequency, 1))
        let high = log10(max(maximumFrequency, minimumFrequency + 1))
        return (0..<count).map { index in
            let fraction = Double(index) / Double(count - 1)
            let frequency = pow(10, low + (high - low) * fraction)
            return EQCurvePoint(
                frequency: frequency,
                gainDB: magnitudeDB(filters: filters, at: frequency, sampleRate: sampleRate)
            )
        }
    }

    /// Highest composite gain over a dense log grid.
    public static func peakDB(
        filters: [FilterSpec],
        sampleRate: Double,
        points: Int = 400
    ) -> Double {
        curve(
            filters: filters,
            sampleRate: sampleRate,
            points: points
        ).map(\.gainDB).max() ?? 0
    }

    /// The preamp that keeps the boosted curve below 0 dBFS, rounded up to
    /// 0.1 dB. A cut-only curve needs no headroom.
    public static func autoPreampDB(
        filters: [FilterSpec],
        sampleRate: Double,
        points: Int = 400
    ) -> Double {
        let peak = peakDB(filters: filters, sampleRate: sampleRate, points: points)
        guard peak > 0 else { return 0 }
        return -(peak * 10).rounded(.up) / 10
    }
}
