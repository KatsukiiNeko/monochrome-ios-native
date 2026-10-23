// TechnicalLabel.swift: compact uppercase monospaced label for structural metadata.
#if canImport(SwiftUI)
import SwiftUI

struct TechnicalLabel: View {
    let text: String
    var color: Color = Theme.secondaryText

    var body: some View {
        Text(text.uppercased())
            .font(Theme.micro)
            .tracking(1.0)
            .foregroundStyle(color)
            .lineLimit(1)
            .accessibilityLabel(text)
    }
}
#endif
