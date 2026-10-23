// PlayerView.swift: Now Playing with artwork tint, seek, transport and queue access.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

struct PlayerView: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isShowingQueue = false
    @State private var tint = Color(ArtworkTintColor.neutral)

    private var player: PlayerController { model.player }

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(spacing: 20) {
                        artwork
                        titleBlock
                        if case .failed(let message) = player.state {
                            errorBlock(message)
                        }
                        Scrubber(
                            position: player.position,
                            duration: player.duration,
                            onSeek: { player.seek(to: $0) }
                        )
                        transportBlock
                        bottomRow
                    }
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
        }
        .task(id: player.currentTrack?.id) {
            tint = Color(await model.artworkTint(for: player.currentTrack))
        }
        .sensoryFeedback(.selection, trigger: player.isPlaying)
        .sheet(isPresented: $isShowingQueue) {
            QueueView(model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.background)
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [tint, Theme.background],
            startPoint: .top,
            endPoint: .center
        )
        .ignoresSafeArea()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: tint)
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close player")

            Spacer(minLength: 0)

            Text(sourceCaption)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)

            Spacer(minLength: 0)

            if !player.queue.isEmpty {
                Menu {
                    Button("Queue", systemImage: "list.bullet") { isShowingQueue = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("More actions")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, Theme.screenPadding)
    }

    private var sourceCaption: String {
        if let album = player.currentTrack?.album, !album.isEmpty {
            return "Playing from \(album)"
        }
        return "Now playing"
    }

    private var artwork: some View {
        TrackArtwork(
            track: player.currentTrack,
            localURL: model.artworkURL(for: player.currentTrack),
            cornerRadius: Theme.albumRadius
        )
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity)
        .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
        .scaleEffect(player.isPlaying || reduceMotion ? 1 : 0.96)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: player.isPlaying)
        .padding(.top, 8)
    }

    private var titleBlock: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(player.currentTrack?.title ?? "Nothing playing")
                    .font(.title.bold())
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(2)
                Text(player.currentTrack?.displayArtist ?? "")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let track = player.currentTrack {
                Button {
                    model.toggleFavorite(track)
                } label: {
                    Image(systemName: model.isFavorite(track) ? "heart.fill" : "heart")
                        .font(.title3)
                        .foregroundStyle(Theme.primaryText)
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
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .accessibilityLabel("Playback error: \(message)")
            Button("Retry") {
                Task { await player.retry() }
            }
            .glassControlStyle()
        }
    }

    private var transportBlock: some View {
        HStack(spacing: 0) {
            repeatControl
                .frame(maxWidth: .infinity)

            Button {
                Task { await player.previous() }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.primaryText)
                    .frame(width: 56, height: 56)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous track")
            .frame(maxWidth: .infinity)

            RoundPlayButton(
                isPlaying: player.isPlaying,
                isLoading: player.state == .loading,
                size: 72
            ) {
                Task { await player.togglePlayPause() }
            }

            Button {
                Task { await player.next() }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.primaryText)
                    .frame(width: 56, height: 56)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next track")
            .frame(maxWidth: .infinity)

            Color.clear
                .frame(width: 44, height: 44)
                .frame(maxWidth: .infinity)
        }
    }

    private var repeatControl: some View {
        Button {
            player.cycleRepeatMode()
        } label: {
            Image(systemName: player.repeatMode.symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(player.repeatMode == .off ? Theme.secondaryText : Theme.primaryText)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(player.repeatMode.label)
    }

    private var bottomRow: some View {
        HStack(spacing: 12) {
            if !player.queue.isEmpty {
                Button {
                    isShowingQueue = true
                } label: {
                    if dynamicTypeSize.isAccessibilitySize {
                        Image(systemName: "list.bullet")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.secondaryText)
                            .frame(width: 44, height: 44)
                    } else {
                        Label("Queue", systemImage: "list.bullet")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open queue")
            }

            if let badge = AudioBadge.text(
                format: player.format,
                quality: player.currentTrack?.audioQuality
            ) {
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
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 4))
                    .accessibilityLabel("Playing from the local cache")
            }

            Spacer(minLength: 8)

            #if canImport(AVKit)
            AirPlayRoutePicker()
                .frame(width: 44, height: 44)
            #endif
        }
        .padding(.top, 4)
    }
}
#endif
