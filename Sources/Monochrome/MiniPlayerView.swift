// MiniPlayerView.swift: floating artwork-tinted card shared by every tab.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

struct MiniPlayerView: View {
    let model: AppModel
    var onOpen: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var tint = Color(ArtworkTintColor.neutral)

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
        if let bar, let track = player.currentTrack {
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    openButton(bar, track: track)
                    favoriteButton(track)
                    controls(bar)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)

                progressBar(bar.progress)
            }
            .background(tint, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Theme.onTintSeparator, lineWidth: Theme.hairline)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 6)
            .animation(reduceMotion ? nil : Theme.standard, value: tint)
            .task(id: track.id) {
                tint = Color(await model.artworkTint(for: track))
            }
        }
    }

    private func openButton(_ bar: NowPlayingBar, track: Track) -> some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                TrackArtwork(
                    track: track,
                    localURL: model.artworkURL(for: track),
                    cornerRadius: Theme.artworkRadius
                )
                .frame(width: Theme.miniArtworkSize, height: Theme.miniArtworkSize)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(bar.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.onTintPrimary)
                            .lineLimit(1)
                        if let badge = bar.badgeText, !dynamicTypeSize.isAccessibilitySize {
                            QualityBadgeLabel(
                                text: badge,
                                spokenText: bar.badgeSpokenText,
                                onTint: true
                            )
                        }
                    }
                    Text(bar.failureMessage == nil ? bar.subtitle : "Playback failed")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.onTintSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open player")
        .accessibilityValue(bar.title)
    }

    private func favoriteButton(_ track: Track) -> some View {
        Button {
            model.toggleFavorite(track)
        } label: {
            Image(systemName: model.isFavorite(track) ? "heart.fill" : "heart")
                .font(.subheadline)
                .foregroundStyle(model.isFavorite(track) ? Theme.onTintAccent : Theme.onTintPrimary)
                .frame(width: Theme.controlSize, height: Theme.controlSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.isFavorite(track) ? "Remove from favorites" : "Add to favorites")
    }

    @ViewBuilder
    private func controls(_ bar: NowPlayingBar) -> some View {
        if bar.isLoading {
            ProgressView()
                .tint(Theme.onTintPrimary)
                .frame(width: Theme.controlSize, height: Theme.controlSize)
                .accessibilityLabel("Loading")
        } else if bar.failureMessage != nil {
            Button {
                Task { await player.retry() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(Theme.onTintPrimary)
                    .frame(width: Theme.controlSize, height: Theme.controlSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retry playback")
        } else {
            Button {
                Task { await player.togglePlayPause() }
            } label: {
                Image(systemName: bar.isPlaying ? "pause.fill" : "play.fill")
                    .foregroundStyle(Theme.onTintPrimary)
                    .frame(width: Theme.controlSize, height: Theme.controlSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(bar.isPlaying ? "Pause" : "Play")
        }

        Button {
            Task { await player.next() }
        } label: {
            Image(systemName: "forward.fill")
                .foregroundStyle(Theme.onTintPrimary)
                .frame(width: Theme.controlSize, height: Theme.controlSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Next track")
    }

    private func progressBar(_ fraction: Double) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.onTintSeparator)
                Rectangle()
                    .fill(Theme.onTintAccent)
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
