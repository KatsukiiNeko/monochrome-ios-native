// QualityBadgeLabel.swift: compact audio-format badge shared by rows and Now Playing.
#if canImport(SwiftUI)
import SwiftUI

struct QualityBadgeLabel: View {
    let text: String
    var spokenText: String?

    var body: some View {
        Text(text.uppercased())
            .font(Theme.micro)
            .tracking(0.4)
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(Theme.border, lineWidth: Theme.hairline)
            }
            .accessibilityLabel(spokenText ?? text)
            .accessibilityAddTraits(.isStaticText)
    }
}
#endif
