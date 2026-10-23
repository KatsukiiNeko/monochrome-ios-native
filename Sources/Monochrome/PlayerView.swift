// PlayerView.swift: full-screen Now Playing with artwork, seek, transport and queue access.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

struct PlayerView: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @State private var isShowingQueue = false

    private var player: PlayerController { model.player }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.spacing) {
                Spacer(minLength: 4)

                TrackArtwork(
                    track: player.currentTrack,
                    localURL: model.artworkURL(for: player.currentTrack),
                    cornerRadius: Theme.corner
                )
                .frame(maxWidth: 340)
                .frame(maxWidth: .infinity)

                titleBlock

                if case .failed(let message) = player.state {
                    errorBlock(message)
                }

                seekBlock
                transportBlock
                repeatControl

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.screenPadding)
            .background(Theme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "chevron.down") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Queue", systemImage: "list.bullet") { isShowingQueue = true }
                        .disabled(player.queue.isEmpty)
                }
            }
            .sheet(isPresented: $isShowingQueue) {
                QueueView(model: model)
            }
        }
    }

    private var titleBlock: some View {
        VStack(spacing: 4) {
            Text(player.currentTrack?.title ?? "Nothing playing")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            // The parsed stream format wins over the tier the catalog declares.
            HStack(spacing: 6) {
                if let badge = AudioBadge.text(format: player.format, quality: player.currentTrack?.audioQuality) {
                    QualityBadgeLabel(
                        text: badge,
                        spokenText: AudioBadge.accessibilityLabel(
                            format: player.format,
                            quality: player.currentTrack?.audioQuality
                        )
                    )
                }
                if player.isCurrentFromCache {
                    Text("Cached")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                        .accessibilityLabel("Playing from the local cache")
                }
            }
            Text(player.currentTrack?.displayArtist ?? "")
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let album = player.currentTrack?.album, !album.isEmpty {
                Text(album)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            if let track = player.currentTrack {
                Button {
                    model.toggleFavorite(track)
                } label: {
                    Image(systemName: model.isFavorite(track) ? "heart.fill" : "heart")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.isFavorite(track) ? "Remove from favorites" : "Add to favorites")
            }
        }
    }

    private func errorBlock(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .accessibilityLabel("Playback error: \(message)")
            Button("Retry") {
                Task { await player.retry() }
            }
            .glassControlStyle()
        }
    }

    private var seekBlock: some View {
        VStack(spacing: 4) {
            Slider(value: positionBinding, in: 0...max(player.duration, 1))
                .accessibilityLabel("Playback position")
                .accessibilityValue(
                    "\(formatDuration(player.position)) of \(formatDuration(player.duration))"
                )
            HStack {
                Text(formatDuration(player.position))
                Spacer()
                Text(formatDuration(player.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var transportBlock: some View {
        HStack(spacing: 36) {
            Button {
                Task { await player.previous() }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title2)
                    .frame(width: 56, height: 56)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous track")

            playPauseButton

            Button {
                Task { await player.next() }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title2)
                    .frame(width: 56, height: 56)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next track")
        }
    }

    @ViewBuilder
    private var playPauseButton: some View {
        if player.state == .loading {
            ProgressView()
                .controlSize(.large)
                .frame(width: 72, height: 72)
                .accessibilityLabel("Loading")
        } else {
            Button {
                Task { await player.togglePlayPause() }
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .frame(width: 72, height: 72)
                    .contentShape(Rectangle())
            }
            .glassControlStyle()
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
        }
    }

    private var repeatControl: some View {
        Button {
            player.cycleRepeatMode()
        } label: {
            Label(player.repeatMode.label, systemImage: player.repeatMode.symbolName)
                .labelStyle(.iconOnly)
                .font(.subheadline)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(player.repeatMode == .off ? Color.secondary : Color.primary)
        .accessibilityLabel(player.repeatMode.label)
    }

    private var positionBinding: Binding<Double> {
        Binding(get: { player.position }, set: { player.seek(to: $0) })
    }
}
#endif
