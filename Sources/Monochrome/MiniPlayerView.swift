// MiniPlayerView.swift: compact now-playing bar shared by every tab.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

struct MiniPlayerView: View {
    let model: AppModel
    var onOpen: () -> Void

    private var player: PlayerController { model.player }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    TrackArtwork(
                        track: player.currentTrack,
                        localURL: model.artworkURL(for: player.currentTrack),
                        cornerRadius: 6
                    )
                    .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.currentTrack?.title ?? "Nothing playing")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(player.currentTrack?.displayArtist ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open player")
            .accessibilityValue(player.currentTrack?.title ?? "")

            Button {
                Task { await player.togglePlayPause() }
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            Button {
                Task { await player.next() }
            } label: {
                Image(systemName: "forward.fill")
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next track")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { progressBar }
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            let fraction = player.duration > 0
                ? min(max(player.position / player.duration, 0), 1)
                : 0
            ZStack(alignment: .leading) {
                Rectangle().fill(.secondary.opacity(0.25))
                Rectangle()
                    .fill(.primary)
                    .frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }
}
#endif
