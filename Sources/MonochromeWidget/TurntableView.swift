// TurntableView.swift: the record, its rotating marks and the tonearm.
#if canImport(WidgetKit)
import MonochromeCore
import SwiftUI

struct TurntableView: View {
    let entry: TurntableEntry

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            // The bottom band is text; the deck gets the rest so the arm never
            // rests behind the title.
            let stage = CGSize(width: proxy.size.width, height: max(0, proxy.size.height - 34))
            let layout = TurntableLayout(size: stage)
            ZStack {
                Plinth()
                RecordBody(layout: layout)
                RecordSheen(layout: layout)
                RecordMarks(layout: layout, artwork: entry.artwork, hasTrack: entry.hasTrack)
                    .rotationEffect(
                        .degrees(entry.frame.platterDegrees),
                        anchor: unitPoint(layout.spindle, in: proxy.size)
                    )
                    .animation(spinAnimation, value: entry.frame.platterDegrees)
                Tonearm(layout: layout, lift: entry.frame.lift)
                    .rotationEffect(
                        .radians(entry.frame.armRotation),
                        anchor: unitPoint(layout.pivot, in: proxy.size)
                    )
                    .animation(armAnimation, value: entry.frame.armRotation)
                    .animation(liftAnimation, value: entry.frame.lift)
                    .widgetAccentable()
                Metadata(entry: entry)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.accessibilityLabel)
    }

    private func unitPoint(_ point: CGPoint, in size: CGSize) -> UnitPoint {
        guard size.width > 0, size.height > 0 else { return .center }
        return UnitPoint(x: point.x / size.width, y: point.y / size.height)
    }

    private var spinAnimation: Animation? {
        reduceMotion || !entry.animate ? nil : .linear(duration: 1.9)
    }
    private var armAnimation: Animation? {
        reduceMotion || !entry.animate ? nil : .easeInOut(duration: 1.8)
    }
    private var liftAnimation: Animation? {
        reduceMotion || !entry.animate ? nil : .easeInOut(duration: 0.6)
    }
}

private struct Plinth: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [WidgetTheme.surface, WidgetTheme.background],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(WidgetTheme.border, lineWidth: 0.5)
            }
    }
}

private struct RecordBody: View {
    let layout: TurntableLayout

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [WidgetTheme.sunken, WidgetTheme.background],
                    center: .center,
                    startRadius: 0,
                    endRadius: layout.recordRadius
                )
            )
            .overlay { Grooves(layout: layout) }
            .overlay { Circle().stroke(WidgetTheme.border, lineWidth: 0.5) }
            .frame(width: layout.recordRadius * 2, height: layout.recordRadius * 2)
            .position(layout.spindle)
            .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
    }
}

private struct Grooves: View {
    let layout: TurntableLayout

    var body: some View {
        Canvas { context, _ in
            let center = CGPoint(x: layout.recordRadius, y: layout.recordRadius)
            let inner = TurntableGeometry.standard.labelRadius * layout.scale
            let step = max(1.5, layout.recordRadius / 26)
            var radius = inner + step
            while radius < layout.recordRadius {
                let rect = CGRect(
                    x: center.x - radius, y: center.y - radius,
                    width: radius * 2, height: radius * 2
                )
                context.stroke(Path(ellipseIn: rect), with: .color(WidgetTheme.border), lineWidth: 0.4)
                radius += step
            }
        }
    }
}

private struct RecordSheen: View {
    let layout: TurntableLayout

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [.white.opacity(0.10), .clear, .white.opacity(0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: layout.recordRadius * 2, height: layout.recordRadius * 2)
            .position(layout.spindle)
            .blendMode(.screen)
            .allowsHitTesting(false)
    }
}

/// Label, artwork, notch and strobe dots: the parts that make rotation visible.
private struct RecordMarks: View {
    let layout: TurntableLayout
    let artwork: Image?
    let hasTrack: Bool

    var body: some View {
        ZStack {
            StrobeDots(layout: layout)
            label
                .position(layout.spindle)
            notch
        }
    }

    private var labelSize: CGFloat { 2 * TurntableGeometry.standard.labelRadius * layout.scale }

    private var label: some View {
        Circle()
            .fill(WidgetTheme.accentSurface)
            .overlay {
                if let artwork {
                    artwork.resizable().scaledToFill()
                } else {
                    Image("monochrome_logo")
                        .resizable()
                        .scaledToFit()
                        .padding(labelSize * 0.22)
                        .opacity(hasTrack ? 0.9 : 0.6)
                }
            }
            .frame(width: labelSize, height: labelSize)
            .clipShape(Circle())
            .overlay { Circle().stroke(WidgetTheme.border, lineWidth: 0.5) }
            .overlay {
                Circle()
                    .fill(WidgetTheme.background)
                    .frame(width: max(2, labelSize * 0.08))
            }
    }

    private var notch: some View {
        Capsule()
            .fill(WidgetTheme.accent)
            .frame(width: max(1.5, layout.scale * 1.2), height: labelSize * 0.16)
            .position(
                x: layout.spindle.x,
                y: layout.spindle.y - labelSize / 2
            )
    }

    private struct StrobeDots: View {
        let layout: TurntableLayout

        var body: some View {
            Canvas { context, _ in
                let count = 60
                let radius = layout.recordRadius * 0.93
                let dot = max(0.8, layout.recordRadius * 0.018)
                for index in 0..<count {
                    let angle = Double(index) / Double(count) * 2 * .pi - .pi / 2
                    let point = CGPoint(
                        x: layout.spindle.x + radius * cos(angle),
                        y: layout.spindle.y + radius * sin(angle)
                    )
                    let rect = CGRect(
                        x: point.x - dot / 2, y: point.y - dot / 2,
                        width: dot, height: dot
                    )
                    context.fill(Path(ellipseIn: rect), with: .color(WidgetTheme.tertiaryText))
                }
            }
            .widgetAccentable()
        }
    }
}

private struct Tonearm: View {
    let layout: TurntableLayout
    let lift: Double

    var body: some View {
        Canvas { context, _ in
            let geometry = TurntableGeometry.standard
            let length = geometry.effectiveLength * layout.scale
            let angle = geometry.restAngle
            let pivot = layout.pivot
            let tip = CGPoint(
                x: pivot.x - length * cos(angle),
                y: pivot.y + length * sin(angle)
            )
            let tail = CGPoint(
                x: pivot.x + 38 * layout.scale * cos(angle),
                y: pivot.y - 38 * layout.scale * sin(angle)
            )

            var tube = Path()
            tube.move(to: tail)
            tube.addLine(to: tip)
            context.stroke(
                tube,
                with: .color(WidgetTheme.primaryText),
                style: StrokeStyle(lineWidth: max(1.2, 2.4 * layout.scale), lineCap: .round)
            )

            let shell = 14 * layout.scale
            let shellAngle = angle - geometry.offsetAngle
            var head = Path()
            head.move(to: tip)
            head.addLine(to: CGPoint(
                x: tip.x - shell * cos(shellAngle),
                y: tip.y + shell * sin(shellAngle)
            ))
            context.stroke(
                head,
                with: .color(WidgetTheme.accent),
                style: StrokeStyle(lineWidth: max(2, 4 * layout.scale), lineCap: .round)
            )

            let base = 7 * layout.scale
            let baseRect = CGRect(
                x: pivot.x - base, y: pivot.y - base,
                width: base * 2, height: base * 2
            )
            context.fill(Path(ellipseIn: baseRect), with: .color(WidgetTheme.primaryText))

            let weight = 9 * layout.scale
            let weightRect = CGRect(
                x: tail.x - weight, y: tail.y - weight,
                width: weight * 2, height: weight * 2
            )
            context.fill(Path(ellipseIn: weightRect), with: .color(WidgetTheme.elevated))
            context.stroke(Path(ellipseIn: weightRect), with: .color(WidgetTheme.border), lineWidth: 0.5)
        }
        // A lifted arm casts a longer, softer shadow.
        .shadow(
            color: .black.opacity(0.35),
            radius: 1 + lift * 5,
            x: 0,
            y: 1 + lift * 4
        )
    }
}

private struct Metadata: View {
    let entry: TurntableEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(entry.title.isEmpty ? (entry.groupAvailable ? "Not playing" : "Open Monochrome") : entry.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WidgetTheme.primaryText)
                .lineLimit(1)
            if !entry.artist.isEmpty {
                Text(entry.artist)
                    .font(.caption2)
                    .foregroundStyle(WidgetTheme.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
}
#endif
