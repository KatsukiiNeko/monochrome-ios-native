// TechnicalIcon.swift: compact bordered icon tile used by technical list rows.
#if canImport(SwiftUI)
import SwiftUI

struct TechnicalIcon: View {
    let name: String
    var destructive = false

    var body: some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(destructive ? Theme.destructive : Theme.primaryText)
            .frame(width: Theme.iconSize, height: Theme.iconSize)
            .background(
                Theme.elevated,
                in: RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                    .stroke(Theme.border, lineWidth: Theme.hairline)
            }
            .accessibilityHidden(true)
    }
}
#endif
