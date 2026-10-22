// MiniPlayerView.swift: compact now-playing bar shared by every tab.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

struct MiniPlayerView: View {
    let model: AppModel
    var onOpen: () -> Void

    private var player: PlayerController { model.player }

    private var bar: NowPlayingBar? {
        NowPlayingBar.make(
            track: player.currentTrack,
            state: player.state,
            position: player.position,
            duration: player.duration,
            format: player.format
        )
    }

    var body: some View {
        if let bar {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    openButton(bar)
                    controls(bar)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                progressBar(bar.progress)
            }
        }
    }

    private func openButton(_ bar: NowPlayingBar) -> some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                TrackArtwork(
                    track: player.currentTrack,
                    localURL: model.artworkURL(for: player.currentTrack),
                    cornerRadius: 6
                )
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(bar.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if let badge = bar.badgeText {
                            QualityBadgeLabel(text: badge, spokenText: bar.badgeSpokenText)
                        }
                    }
                    Text(bar.failureMessage ?? bar.subtitle)
                        .font(.caption)
                        .foregroundStyle(bar.failureMessage == nil ? Color.secondary : Color.red)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open player")
        .accessibilityValue(bar.title)
    }

    @ViewBuilder
    private func controls(_ bar: NowPlayingBar) -> some View {
        if bar.isLoading {
            ProgressView()
                .frame(width: 36, height: 36)
                .accessibilityLabel("Loading")
        } else if bar.failureMessage != nil {
            Button {
                Task { await player.retry() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retry playback")
        } else {
            Button {
                Task { await player.togglePlayPause() }
            } label: {
                Image(systemName: bar.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(bar.isPlaying ? "Pause" : "Play")
        }

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

    private func progressBar(_ fraction: Double) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle().fill(.secondary.opacity(0.25))
                Rectangle()
                    .fill(.primary)
                    .frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: 2)
        .accessibilityElement()
        .accessibilityLabel("Playback progress")
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
    }
}
#endif
