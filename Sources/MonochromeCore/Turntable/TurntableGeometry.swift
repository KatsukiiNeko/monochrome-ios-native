// TurntableGeometry.swift: the arm geometry shared by the widget and the app.
import Foundation

/// Millimetres, with IEC groove radii and a 9-inch Baerwald arm.
public struct TurntableGeometry: Sendable {
    public static let standard = TurntableGeometry()

    public var recordRadius = 150.0
    public var outerGrooveRadius = 146.05
    public var innerGrooveRadius = 60.325
    public var labelRadius = 50.0
    public var effectiveLength = 228.6
    public var nullInner = 66.0
    public var nullOuter = 120.9
    public var restRadius = 190.0

    public init() {}

    /// Spindle to pivot distance (Löfgren): d² = L² − r1·r2.
    public var pivotDistance: Double {
        (effectiveLength * effectiveLength - nullInner * nullOuter).squareRoot()
    }

    /// Headshell offset angle: β = asin((r1 + r2) / 2L).
    public var offsetAngle: Double {
        asin((nullInner + nullOuter) / (2 * effectiveLength))
    }

    /// Angle at the pivot between the spindle and the stylus.
    public func armAngle(stylusRadius r: Double) -> Double {
        let d = pivotDistance, l = effectiveLength
        let c = (d * d + l * l - r * r) / (2 * d * l)
        return acos(min(1, max(-1, c)))
    }

    /// 0 = start of the music, 1 = end; the groove radius shrinks linearly.
    public func stylusRadius(progress: Double) -> Double {
        let t = min(1, max(0, progress))
        return outerGrooveRadius - t * (outerGrooveRadius - innerGrooveRadius)
    }

    public var restAngle: Double { armAngle(stylusRadius: restRadius) }

    /// Clockwise rotation of an arm drawn at rest, in radians. Positive is
    /// clockwise on screen, where y points down.
    public func armRotation(progress: Double) -> Double {
        restAngle - armAngle(stylusRadius: stylusRadius(progress: progress))
    }
}
