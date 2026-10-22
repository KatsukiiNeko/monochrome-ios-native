// TrackRow.swift: one track row shared by the library, search, home and queue.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

struct TrackRow: View {
    let track: Track
    var localArtworkURL: URL?
    var isCurrent = false
    var showsFavorite = false
    var isFavorite = false
    var showsDuration = true

    var body: some View {
        HStack(spacing: 12) {
            TrackArtwork(track: track, localURL: localArtworkURL, cornerRadius: 6)
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                    .lineLimit(1)
                Text(track.displayArtist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if showsFavorite, isFavorite {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Favorite")
            }
            if showsDuration, let duration = track.durationSeconds {
                Text(formatDuration(duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Plays this track")
    }
}
#endif
