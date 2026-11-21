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
    public var degreesPerSecond = PlaybackSnapshot.platterDegreesPerSecond
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

        guard s.isPlaying, mode == .spin else {
            return [TurntableFrame(
                date: now,
                platterDegrees: platterNow,
                armRotation: arm(at: elapsed, duration: duration),
                lift: 0
            )]
        }

        var out: [TurntableFrame] = []
        var k = 0
        while out.count < maxFrames {
            let t = Double(k) * step
            let songTime = elapsed + t
            if songTime >= duration { break }
            // The drop is keyed to the actual start, not to this timeline run,
            // so a reload a few seconds late still picks up the arm mid-drop.
            let sinceStart = s.playStartedAt.map { now.addingTimeInterval(t).timeIntervalSince($0) }
            out.append(TurntableFrame(
                date: now.addingTimeInterval(t),
                platterDegrees: platterNow + degreesPerSecond * t,
                armRotation: arm(at: songTime, duration: duration, sinceStart: sinceStart),
                lift: lift(sinceStart: sinceStart)
            ))
            k += 1
        }
        if out.isEmpty {
            return [TurntableFrame(
                date: now,
                platterDegrees: platterNow,
                armRotation: arm(at: duration, duration: duration),
                lift: 0
            )]
        }
        return out
    }

    private func arm(at songTime: TimeInterval, duration: TimeInterval) -> Double {
        geometry.armRotation(progress: songTime / duration)
    }

    /// Parked until the first step, swung over the groove until `dropWindow`,
    /// then lowered onto it.
    private func arm(at songTime: TimeInterval, duration: TimeInterval, sinceStart: TimeInterval?) -> Double {
        guard let sinceStart, sinceStart < dropWindow, sinceStart < step else {
            return arm(at: songTime, duration: duration)
        }
        return 0
    }

    private func lift(sinceStart: TimeInterval?) -> Double {
        guard let sinceStart, sinceStart < dropWindow else { return 0 }
        return 1
    }
}
