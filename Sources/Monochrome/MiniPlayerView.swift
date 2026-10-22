// MiniPlayerView.swift: compact now-playing bar pinned above the library list.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

struct MiniPlayerView: View {
    let player: PlayerController
    var onOpen: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.currentTrack?.title ?? "Nothing playing")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(player.currentTrack?.displayArtist ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open player")
            .accessibilityValue(player.currentTrack?.title ?? "")

            Button {
                Task { await player.togglePlayPause() }
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            Button {
                Task { await player.next() }
            } label: {
                Image(systemName: "forward.fill")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next track")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
#endif
