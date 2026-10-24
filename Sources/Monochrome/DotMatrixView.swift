// DotMatrixView.swift: the decorative 5x7 glyph renderer and section headers.
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

/// Display-only dot-matrix label. At accessibility sizes it falls back to the
/// scalable monospaced label, so the decorative face never blocks reading.
struct DotMatrixLabel: View {
    let text: String
    var color: Color = Theme.secondaryText
    var dotSize: CGFloat = 1.7

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption2) private var scale: CGFloat = 1

    private var usesDotMatrix: Bool {
        !dynamicTypeSize.isAccessibilitySize && DotMatrix.supports(text.uppercased())
    }

    private var matrix: some View {
        DotMatrixText(
            text: text.uppercased(),
            dotSize: dotSize * min(scale, 1.25),
            dotSpacing: 1,
            characterSpacing: 3,
            color: color
        )
        .accessibilityLabel(text)
    }

    var body: some View {
        if usesDotMatrix {
            // Long headings and narrow columns fall back to the scalable mono
            // label rather than clipping a fixed-width dot grid.
            ViewThatFits(in: .horizontal) {
                matrix
                TechnicalLabel(text: text, color: color)
            }
        } else {
            TechnicalLabel(text: text, color: color)
        }
    }
}

/// Structural heading shared by native lists: technical marker, dot-matrix
/// label and optional compact metadata.
struct TechnicalSectionHeader: View {
    let title: String
    var meta: String?

    @Environment(\.accentColor) private var accent

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Rectangle()
                .fill(accent)
                .frame(width: Theme.sectionMarker, height: Theme.markerHeight)
                .accessibilityHidden(true)

            DotMatrixLabel(text: title)

            Spacer(minLength: 8)

            if let meta {
                TechnicalLabel(text: meta)
            }
        }
        .textCase(nil)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
#endif
