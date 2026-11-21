// TurntableLayoutTests.swift: the layout fits small and medium widget sizes.
import Foundation
import Testing
@testable import MonochromeCore

@Suite("Turntable layout")
struct TurntableLayoutTests {
    let geometry = TurntableGeometry()

    func bounds(_ rect: CGSize) -> TurntableLayout {
        TurntableLayout(size: rect, geometry: geometry)
    }

    @Test func theRestPoseAndPivotStayInsideTheSmallWidget() {
        let size = CGSize(width: 158, height: 158)
        let layout = bounds(size)
        #expect(layout.recordRadius > 0)
        #expect(layout.spindle.x - layout.recordRadius >= 0)
        #expect(layout.pivot.x + 22 * layout.scale <= size.width)
        #expect(layout.restTip.x >= 0 && layout.restTip.x <= size.width)
        #expect(layout.restTip.y >= 0 && layout.restTip.y <= size.height)
    }

    @Test func theMediumWidgetUsesTheSameFit() {
        let size = CGSize(width: 338, height: 158)
        let layout = bounds(size)
        #expect(layout.pivot.x + 22 * layout.scale <= size.width)
        #expect(layout.restTip.y <= size.height)
    }

    @Test func aWideWidgetCentresTheDeck() {
        let size = CGSize(width: 338, height: 124)
        let layout = bounds(size)
        let left = layout.spindle.x - layout.recordRadius
        let right = layout.pivot.x + 40 * layout.scale
        #expect(abs(left - (size.width - right)) < 0.5)
    }

    @Test func theRestTipIsOutsideTheRecord() {
        let layout = bounds(CGSize(width: 158, height: 158))
        let distance = hypot(layout.restTip.x - layout.spindle.x, layout.restTip.y - layout.spindle.y)
        #expect(distance > layout.recordRadius)
    }

    @Test func theStylusLandsOnTheGroove() throws {
        let layout = bounds(CGSize(width: 158, height: 158))
        let tip = try #require(layout.tip(progress: 0))
        let distance = hypot(tip.x - layout.spindle.x, tip.y - layout.spindle.y)
        #expect(abs(distance - geometry.outerGrooveRadius * layout.scale) < 0.001)
    }
}
