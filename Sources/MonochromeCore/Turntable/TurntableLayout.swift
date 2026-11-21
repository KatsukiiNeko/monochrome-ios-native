// TurntableLayout.swift: geometry in millimetres mapped onto a widget rectangle.
import Foundation

public struct TurntableLayout: Sendable {
    public let size: CGSize
    /// Points per millimetre.
    public let scale: CGFloat
    public let spindle: CGPoint
    public let pivot: CGPoint
    public let recordRadius: CGFloat
    /// Stylus tip when the arm is parked at rest.
    public let restTip: CGPoint

    public init(size: CGSize, geometry: TurntableGeometry = .init(), margin: CGFloat = 8) {
        self.size = size
        let usableWidth = max(0, size.width - 2 * margin)
        let usableHeight = max(0, size.height - 2 * margin)
        let restDrop = geometry.effectiveLength * sin(geometry.restAngle)
        // The tail of the arm and its base need room to the right of the pivot.
        let horizontal = geometry.recordRadius + geometry.pivotDistance + 40
        let vertical = geometry.recordRadius + restDrop
        scale = min(usableWidth / horizontal, usableHeight / vertical)
        recordRadius = geometry.recordRadius * scale
        // Centre the record-to-rest span vertically; the record sits high.
        let spindleY = size.height / 2 - (restDrop - geometry.recordRadius) * scale / 2
        // Centre the whole deck horizontally, with the margin as the floor.
        let deckWidth = horizontal * scale
        let left = max(margin, (size.width - deckWidth) / 2)
        spindle = CGPoint(x: left + recordRadius, y: spindleY)
        pivot = CGPoint(x: spindle.x + geometry.pivotDistance * scale, y: spindle.y)
        let angle = geometry.restAngle
        restTip = CGPoint(
            x: pivot.x - geometry.effectiveLength * scale * cos(angle),
            y: pivot.y + geometry.effectiveLength * scale * sin(angle)
        )
    }

    /// Stylus tip for a song progress; nil when the rectangle is too small.
    public func tip(progress: Double, geometry: TurntableGeometry = .init()) -> CGPoint? {
        guard scale > 0 else { return nil }
        let angle = geometry.armAngle(stylusRadius: geometry.stylusRadius(progress: progress))
        return CGPoint(
            x: pivot.x - geometry.effectiveLength * scale * cos(angle),
            y: pivot.y + geometry.effectiveLength * scale * sin(angle)
        )
    }
}
