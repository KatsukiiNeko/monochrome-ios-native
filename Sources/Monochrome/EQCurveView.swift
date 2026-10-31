// EQCurveView.swift: the response curve and the vertical band faders.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

/// Draws the composite response on a log frequency axis. Decorative for
/// VoiceOver; the sliders and the text summary carry the values.
struct EQCurveView: View {
    let filters: [FilterSpec]
    let sampleRate: Double
    let graphicGains: [Double]
    let selectedBand: Int?
    var onSelectBand: ((Int) -> Void)?

    @Environment(\.accentColor) private var accent

    private let range = 12.0

    var body: some View {
        Canvas { context, size in
            drawGrid(in: &context, size: size)
            drawCurve(in: &context, size: size)
            drawHandles(in: &context, size: size)
        }
        .frame(height: 150)
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.border, lineWidth: Theme.hairline)
        }
        .accessibilityHidden(true)
    }

    private func x(for frequency: Double, width: CGFloat) -> CGFloat {
        let low = log10(EQResponse.defaultMinimumFrequency)
        let high = log10(EQResponse.defaultMaximumFrequency)
        let fraction = (log10(max(frequency, 1)) - low) / (high - low)
        return CGFloat(min(max(fraction, 0), 1)) * width
    }

    private func y(for gain: Double, height: CGFloat) -> CGFloat {
        let clamped = min(max(gain, -range), range)
        return height / 2 - CGFloat(clamped / range) * (height / 2 - 8)
    }

    private func drawGrid(in context: inout GraphicsContext, size: CGSize) {
        var zero = Path()
        zero.move(to: CGPoint(x: 0, y: size.height / 2))
        zero.addLine(to: CGPoint(x: size.width, y: size.height / 2))
        context.stroke(zero, with: .color(Theme.separator), lineWidth: Theme.hairline)

        for frequency in EQGraphicBands.frequencies {
            var line = Path()
            let position = x(for: frequency, width: size.width)
            line.move(to: CGPoint(x: position, y: 0))
            line.addLine(to: CGPoint(x: position, y: size.height))
            context.stroke(line, with: .color(Theme.separator.opacity(0.6)), lineWidth: Theme.hairline)
        }
    }

    private func drawCurve(in context: inout GraphicsContext, size: CGSize) {
        let points = EQResponse.curve(filters: filters, sampleRate: sampleRate, points: 160)
        guard points.count > 1 else { return }
        var path = Path()
        for (index, point) in points.enumerated() {
            let position = CGPoint(
                x: x(for: point.frequency, width: size.width),
                y: y(for: point.gainDB, height: size.height)
            )
            if index == 0 {
                path.move(to: position)
            } else {
                path.addLine(to: position)
            }
        }
        context.stroke(path, with: .color(accent), lineWidth: 2)

        var fill = path
        fill.addLine(to: CGPoint(x: size.width, y: size.height / 2))
        fill.addLine(to: CGPoint(x: 0, y: size.height / 2))
        fill.closeSubpath()
        context.fill(fill, with: .color(accent.opacity(0.12)))
    }

    private func drawHandles(in context: inout GraphicsContext, size: CGSize) {
        for (index, frequency) in EQGraphicBands.frequencies.enumerated() {
            let gain = index < graphicGains.count ? graphicGains[index] : 0
            let centre = CGPoint(
                x: x(for: frequency, width: size.width),
                y: y(for: gain, height: size.height)
            )
            let radius: CGFloat = index == selectedBand ? 5 : 3
            let dot = Path(
                ellipseIn: CGRect(
                    x: centre.x - radius,
                    y: centre.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
            )
            context.fill(dot, with: .color(index == selectedBand ? accent : Theme.secondaryText))
        }
    }
}

/// One vertical band control. A drag maps linearly to ±12 dB in 0.5 dB steps,
/// and the accessibility actions do the same for VoiceOver.
struct EQBandFader: View {
    let frequency: Double
    let gain: Double
    let isSelected: Bool
    let onGain: (Double) -> Void
    let onSelect: () -> Void

    @Environment(\.accentColor) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let height: CGFloat = 132
    private let range = EQGraphicBands.maxGainDB

    var body: some View {
        VStack(spacing: 6) {
            Text(gainLabel)
                .font(Theme.micro)
                .monospacedDigit()
                .foregroundStyle(gain == 0 ? Theme.tertiaryText : Theme.primaryText)

            ZStack {
                Capsule()
                    .fill(Theme.sunken)
                    .frame(width: 4)
                Capsule()
                    .fill(accent)
                    .frame(width: 4, height: thumbSpace)
                    .frame(maxHeight: .infinity, alignment: .center)
                Circle()
                    .fill(isSelected ? accent : Theme.elevated)
                    .overlay {
                        Circle().stroke(isSelected ? accent : Theme.border, lineWidth: Theme.hairline)
                    }
                    .frame(width: isSelected ? 22 : 18, height: isSelected ? 22 : 18)
                    .offset(y: offset)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    .animation(reduceMotion ? nil : Theme.quick, value: isSelected)
            }
            .frame(height: height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onSelect()
                        let position = min(max(value.location.y, 0), height)
                        let fraction = 1 - (position / height)
                        let raw = (fraction * 2 - 1) * range
                        onGain((raw * 2).rounded() / 2)
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(frequencyLabel)
            .accessibilityValue(gainSpoken)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: onGain(min(gain + 0.5, range))
                case .decrement: onGain(max(gain - 0.5, -range))
                @unknown default: break
                }
            }
            .accessibilityHint("Adjusts this band. Double tap and hold, then slide up or down.")

            Text(shortFrequency)
                .font(Theme.micro)
                .foregroundStyle(Theme.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .onTapGesture(count: 2) { onGain(0) }
    }

    private var thumbSpace: CGFloat { 2 }

    private var offset: CGFloat {
        let fraction = min(max(gain / range, -1), 1)
        return -fraction * (height / 2 - 12)
    }

    private var gainLabel: String {
        let rounded = (gain * 2).rounded() / 2
        if rounded == 0 { return "0" }
        return String(format: "%+.1f", rounded)
    }

    private var gainSpoken: String {
        let rounded = (gain * 2).rounded() / 2
        if rounded == 0 { return "flat" }
        return "\(String(format: "%+.1f", rounded)) decibels"
    }

    private var frequencyLabel: String {
        frequency < 1_000
            ? "\(Int(frequency)) hertz"
            : "\(Int(frequency / 1_000)) kilohertz"
    }

    private var shortFrequency: String {
        frequency < 1_000 ? "\(Int(frequency))" : "\(Int(frequency / 1_000))k"
    }
}
#endif
