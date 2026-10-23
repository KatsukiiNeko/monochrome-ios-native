// ArtworkTile.swift: square artwork with title and subtitle, used by shelves and grids.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

struct ArtworkTile: View {
    let track: Track
    var localArtworkURL: URL?
    var width: CGFloat = 132
    var accessibilityLabel: String?
    var accessibilityHint = "Plays this track"
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                TrackArtwork(
                    track: track,
                    localURL: localArtworkURL,
                    cornerRadius: Theme.albumRadius
                )
                .frame(width: width, height: width)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.albumRadius, style: .continuous)
                        .stroke(Theme.border, lineWidth: Theme.hairline)
                }

                Text(track.title)
                    .font(Theme.rowTitle)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                Text(track.displayArtist)
                    .font(Theme.rowSubtitle)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? "\(track.title) by \(track.displayArtist)")
        .accessibilityHint(accessibilityHint)
    }
}
#endif
