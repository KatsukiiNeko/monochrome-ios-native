// PlayerView.swift: full-screen player with seek, transport and error state.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

struct PlayerView: View {
    let player: PlayerController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer(minLength: 8)
                Image(systemName: "waveform")
                    .font(.system(size: 96, weight: .thin))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                VStack(spacing: 4) {
                    Text(player.currentTrack?.title ?? "Nothing playing")
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text(player.currentTrack?.displayArtist ?? "")
                        .foregroundStyle(.secondary)
                    if let album = player.currentTrack?.album, !album.isEmpty {
                        Text(album)
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                }

                if case .failed(let message) = player.state {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .accessibilityLabel("Playback error: \(message)")
                }

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

                HStack(spacing: 44) {
                    Button {
                        Task { await player.previous() }
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.title2)
                    }
                    .accessibilityLabel("Previous track")

                    playPauseButton

                    Button {
                        Task { await player.next() }
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.title2)
                    }
                    .accessibilityLabel("Next track")
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "chevron.down") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var positionBinding: Binding<Double> {
        Binding(get: { player.position }, set: { player.seek(to: $0) })
    }

    @ViewBuilder
    private var playPauseButton: some View {
        if player.state == .loading {
            ProgressView()
                .controlSize(.large)
                .frame(width: 64, height: 64)
                .accessibilityLabel("Loading")
        } else {
            Button {
                Task { await player.togglePlayPause() }
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
        }
    }
}
#endif
