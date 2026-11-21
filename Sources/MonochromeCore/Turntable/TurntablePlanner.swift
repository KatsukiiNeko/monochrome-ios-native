// TurntablePlanner.swift: snapshot plus clock in, timeline frames out.
import Foundation

public enum MotionMode: Sendable {
    case spin
    case still
}

public struct TurntableFrame: Equatable, Sendable {
    public var date: Date
    /// Continuous angle; never wraps, so animation always turns forward.
    public var platterDegrees: Double
    /// Radians clockwise from the rest pose.
    public var armRotation: Double
    /// 0 = stylus in the groove, 1 = clear of the record.
    public var lift: Double

    public init(date: Date, platterDegrees: Double, armRotation: Double, lift: Double) {
        self.date = date
        self.platterDegrees = platterDegrees
        self.armRotation = armRotation
        self.lift = lift
    }
}

public struct TurntablePlanner: Sendable {
    public var geometry = TurntableGeometry()
    public var degreesPerSecond = 200.0
    /// About the fastest cadence WidgetKit shows.
    public var step: TimeInterval = 2
    public var maxFrames = 150
    public var dropWindow: TimeInterval = 4

    public init() {}

    public func frames(for s: PlaybackSnapshot, now: Date, mode: MotionMode) -> [TurntableFrame] {
        guard s.trackID != nil, let duration = s.duration, duration > 0 else {
            return [TurntableFrame(date: now, platterDegrees: s.platterDegrees, armRotation: 0, lift: 1)]
        }
        let elapsed = s.elapsed(at: now)
        let platterNow = s.platter(at: now)
        func arm(_ t: TimeInterval) -> Double {
            geometry.armRotation(progress: t / duration)
        }

        guard s.isPlaying, mode == .spin else {
            return [TurntableFrame(date: now, platterDegrees: platterNow, armRotation: arm(elapsed), lift: 0)]
        }

        var out: [TurntableFrame] = []
        var k = 0
        if let started = s.playStartedAt, now.timeIntervalSince(started) < dropWindow {
            // Parked and lifted, swing over the groove still lifted, then lower.
            out.append(TurntableFrame(date: now, platterDegrees: platterNow, armRotation: 0, lift: 1))
            out.append(TurntableFrame(
                date: now + step,
                platterDegrees: platterNow + degreesPerSecond * step,
                armRotation: arm(elapsed + step),
                lift: 1
            ))
            k = 2
        }
        while out.count < maxFrames {
            let t = Double(k) * step
            if elapsed + t >= duration { break }
            out.append(TurntableFrame(
                date: now + t,
                platterDegrees: platterNow + degreesPerSecond * t,
                armRotation: arm(elapsed + t),
                lift: 0
            ))
            k += 1
        }
        if out.isEmpty {
            return [TurntableFrame(date: now, platterDegrees: platterNow, armRotation: arm(duration), lift: 0)]
        }
        return out
    }
}
