// ShelfHeader.swift: section title with an optional See all action.
#if canImport(SwiftUI)
import SwiftUI

struct ShelfHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Theme.sectionTitle)
                .foregroundStyle(Theme.primaryText)
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}
#endif
