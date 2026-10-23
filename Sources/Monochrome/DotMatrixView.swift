// DotMatrixView.swift: the decorative 5x7 glyph renderer and cache slot meter.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

struct DotMatrixText: View {
    let text: String
    var dotSize: CGFloat = 2
    var dotSpacing: CGFloat = 1
    var characterSpacing: CGFloat = 3
    var color: Color = Theme.primaryText

    private var width: CGFloat {
        let count = CGFloat(text.count)
        guard count > 0 else { return 0 }
        return count * (5 * dotSize + 4 * dotSpacing) + (count - 1) * characterSpacing
    }

    private var height: CGFloat {
        7 * dotSize + 6 * dotSpacing
    }

    var body: some View {
        Canvas { context, _ in
            var originX: CGFloat = 0
            for character in text {
                guard let glyph = DotMatrix.glyph(for: character) else {
                    originX += 5 * dotSize + 4 * dotSpacing + characterSpacing
                    continue
                }
                for (rowIndex, row) in glyph.rows.enumerated() {
                    for (columnIndex, value) in row.enumerated() where value == "#" {
                        let rect = CGRect(
                            x: originX + CGFloat(columnIndex) * (dotSize + dotSpacing),
                            y: CGFloat(rowIndex) * (dotSize + dotSpacing),
                            width: dotSize,
                            height: dotSize
                        )
                        context.fill(Path(ellipseIn: rect), with: .color(color))
                    }
                }
                originX += 5 * dotSize + 4 * dotSpacing + characterSpacing
            }
        }
        .frame(width: width, height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

struct CacheSlotMeter: View {
    let used: Int
    let total: Int

    private var boundedUsed: Int { min(max(used, 0), total) }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index < boundedUsed ? Theme.accent : Theme.sunken)
                    .frame(width: 10, height: 10)
                    .overlay {
                        Circle()
                            .stroke(
                                index < boundedUsed ? Theme.accent : Theme.border,
                                lineWidth: Theme.hairline
                            )
                    }
            }
        }
        .animation(.easeOut(duration: 0.18), value: boundedUsed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(boundedUsed) of \(total) cache slots used")
    }
}
#endif
