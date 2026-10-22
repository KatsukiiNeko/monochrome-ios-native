// QualityBadgeLabel.swift: compact audio-format badge shared by rows and Now Playing.
#if canImport(SwiftUI)
import SwiftUI

struct QualityBadgeLabel: View {
    let text: String
    var spokenText: String?

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            .accessibilityLabel(spokenText ?? text)
            .accessibilityAddTraits(.isStaticText)
    }
}
#endif
