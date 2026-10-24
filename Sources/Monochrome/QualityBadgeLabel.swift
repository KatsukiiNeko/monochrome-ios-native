// QualityBadgeLabel.swift: compact audio-format badge shared by rows and Now Playing.
#if canImport(SwiftUI)
import SwiftUI

struct QualityBadgeLabel: View {
    let text: String
    var spokenText: String?
    var onTint = false

    private var foreground: Color { onTint ? Theme.onTintPrimary : Theme.secondaryText }
    private var background: Color { onTint ? Color.white.opacity(0.12) : Theme.surface }
    private var border: Color { onTint ? Theme.onTintSeparator : Theme.border }

    var body: some View {
        Text(text.uppercased())
            .font(Theme.micro)
            .tracking(0.4)
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(background, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(border, lineWidth: Theme.hairline)
            }
            .accessibilityLabel(spokenText ?? text)
            .accessibilityAddTraits(.isStaticText)
    }
}
#endif
