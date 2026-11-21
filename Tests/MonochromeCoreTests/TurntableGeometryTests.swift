// TurntableGeometryTests.swift: golden values from the Baerwald arm geometry.
import Testing
@testable import MonochromeCore

@Suite("Turntable geometry")
struct TurntableGeometryTests {
    let g = TurntableGeometry()

    func deg(_ r: Double) -> Double { r * 180 / .pi }

    @Test func derivedConstantsMatchTheStandardGeometry() {
        #expect(abs(g.pivotDistance - 210.42) < 0.01)
        #expect(abs(deg(g.offsetAngle) - 24.13) < 0.01)
    }

    @Test func armAnglesAtKnownRadii() {
        #expect(abs(deg(g.armAngle(stylusRadius: 146.05)) - 38.582) < 0.01)
        #expect(abs(deg(g.armAngle(stylusRadius: 103.188)) - 26.778) < 0.01)
        #expect(abs(deg(g.armAngle(stylusRadius: 60.325)) - 15.070) < 0.01)
        #expect(abs(deg(g.restAngle) - 51.083) < 0.01)
    }

    @Test func theArmSweepsAcrossASideAndOnlyOneWay() {
        #expect(abs(deg(g.armRotation(progress: 1) - g.armRotation(progress: 0)) - 23.512) < 0.01)
        var last = -Double.infinity
        for i in 0...100 {
            let r = g.armRotation(progress: Double(i) / 100)
            #expect(r >= last)
            last = r
        }
    }

    @Test func progressIsClampedAndTheRestPoseIsNeutral() {
        #expect(g.armRotation(progress: -3) == g.armRotation(progress: 0))
        #expect(g.armRotation(progress: 9) == g.armRotation(progress: 1))
        #expect(g.restAngle - g.armAngle(stylusRadius: g.restRadius) == 0)
    }
}
