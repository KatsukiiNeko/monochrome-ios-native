// ShelfHeader.swift: section title with a state marker and an optional See all action.
#if canImport(SwiftUI)
import SwiftUI

struct ShelfHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Rectangle()
                .fill(Theme.accent)
                .frame(width: Theme.sectionMarker, height: 14)
                .accessibilityHidden(true)

            Text(title)
                .font(Theme.sectionTitle)
                .foregroundStyle(Theme.primaryText)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 8)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(Theme.technical)
                    .tracking(0.6)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}
#endif
