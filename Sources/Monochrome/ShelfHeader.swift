// ShelfHeader.swift: section title with a state marker and an optional See all action.
#if canImport(SwiftUI)
import SwiftUI

struct ShelfHeader: View {
    let title: String
    var meta: String?
    var actionTitle: String?
    var action: (() -> Void)?

    @Environment(\.accentColor) private var accent

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Rectangle()
                .fill(accent)
                .frame(width: Theme.sectionMarker, height: Theme.markerHeight)
                .accessibilityHidden(true)

            Text(title)
                .font(Theme.shelfTitle)
                .foregroundStyle(Theme.primaryText)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 8)

            if let meta {
                TechnicalLabel(text: meta)
            }

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
