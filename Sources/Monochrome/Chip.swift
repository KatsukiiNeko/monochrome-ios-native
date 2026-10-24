// Chip.swift: selectable filter chip with a technical rectangular shape.
#if canImport(SwiftUI)
import SwiftUI

struct Chip: View {
    let title: String
    let isSelected: Bool
    var action: () -> Void

    @Environment(\.accentColor) private var accent
    @Environment(\.onAccentColor) private var onAccent

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .tracking(0.2)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(isSelected ? onAccent : Theme.primaryText)
                .background(isSelected ? accent : Theme.surface, in: shape)
                .overlay {
                    if !isSelected {
                        shape.stroke(Theme.border, lineWidth: Theme.hairline)
                    }
                }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
#endif
