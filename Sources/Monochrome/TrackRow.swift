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
    /// Overrides the default artist subtitle, e.g. "Song · Artist" in search.
    var subtitle: String?
    var showsKind = false

    private var rowSubtitle: String {
        if let subtitle { return subtitle }
        return showsKind ? "Song · \(track.displayArtist)" : track.displayArtist
    }

    var body: some View {
        HStack(spacing: Theme.rowSpacing) {
            TrackArtwork(
                track: track,
                localURL: localArtworkURL,
                cornerRadius: Theme.artworkRadius
            )
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if isCurrent {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.primaryText)
                            .accessibilityLabel("Now playing")
                    }
                    Text(track.title)
                        .font(Theme.rowTitle)
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    if let badge = AudioBadge.text(quality: track.audioQuality) {
                        QualityBadgeLabel(
                            text: badge,
                            spokenText: AudioBadge.accessibilityLabel(quality: track.audioQuality)
                        )
                        .layoutPriority(1)
                    }
                }
                Text(rowSubtitle)
                    .font(Theme.rowSubtitle)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if showsFavorite, isFavorite {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityLabel("Favorite")
            }
            if showsDuration, let duration = track.durationSeconds {
                Text(formatDuration(duration))
                    .font(Theme.time)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Plays this track")
    }
}
#endif
