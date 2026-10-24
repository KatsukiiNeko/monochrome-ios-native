// PlayerView.swift: Now Playing with artwork tint, seek, transport and queue access.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

struct PlayerView: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentColor) private var accent
    @State private var isShowingQueue = false
    @State private var isShowingAudioSpec = false
    @State private var isShowingLyrics = false
    @State private var outputMonitor = AudioOutputMonitor()
    @State private var tint = Color(ArtworkTintColor.neutral)
    @State private var pendingDownloadRemoval: DownloadItem?

    private var player: PlayerController { model.player }

    private var audioSpec: AudioSpec {
        let source: AudioPlaybackSource
        if player.isCurrentFromDownload {
            source = .download
        } else if player.isCurrentFromCache {
            source = .cache
        } else if player.currentTrack?.isStreaming == true {
            source = .stream
        } else {
            source = .local
        }
        return AudioSpec.from(
            format: player.format,
            quality: player.currentTrack?.audioQuality,
            source: source,
            output: outputMonitor.output
        )
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            background

            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(spacing: 20) {
                        artwork
                        titleBlock
                        audioInfoLine
                        if case .failed(let message) = player.state {
                            errorBlock(message)
                        }
                        Scrubber(
                            position: player.position,
                            duration: player.duration,
                            onSeek: { player.seek(to: $0) }
                        )
                        transportBlock
                        actionRow
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
        .preferredColorScheme(model.appearanceMode.colorScheme)
        .sheet(isPresented: $isShowingQueue) {
            QueueView(model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.background)
        }
        .sheet(isPresented: $isShowingAudioSpec) {
            AudioSpecView(spec: audioSpec, outputMonitor: outputMonitor)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.background)
        }
        .sheet(isPresented: $isShowingLyrics) {
            LyricsView(model: model)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.background)
        }
        .confirmationDialog(
            "Remove “\(pendingDownloadRemoval?.track.title ?? "this download")”?",
            isPresented: Binding(
                get: { pendingDownloadRemoval != nil },
                set: { if !$0 { pendingDownloadRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove download", role: .destructive) {
                guard let item = pendingDownloadRemoval else { return }
                pendingDownloadRemoval = nil
                Task { await model.removeDownload(item) }
            }
            Button("Cancel", role: .cancel) { pendingDownloadRemoval = nil }
        } message: {
            Text("The offline copy is deleted. You can download it again later.")
        }
    }

    @ViewBuilder
    private func downloadAction(_ track: Track) -> some View {
        if let state = model.downloadState(for: track) {
            switch state {
            case .completed:
                Button("Remove download", systemImage: "trash", role: .destructive) {
                    pendingDownloadRemoval = model.downloads.first {
                        $0.track.id == track.id && $0.state == .completed
                    }
                }
            case .queued, .downloading:
                Label("Downloading…", systemImage: "arrow.down.circle")
            case .failed:
                Button("Retry download", systemImage: "arrow.clockwise") {
                    model.startDownload(track)
                }
            case .cancelled:
                Button("Download", systemImage: "arrow.down.circle") {
                    model.startDownload(track)
                }
            }
        } else {
            Button("Download", systemImage: "arrow.down.circle") {
                model.startDownload(track)
            }
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                colorScheme == .light ? tint.opacity(0.12) : tint.opacity(0.60),
                Theme.background
            ],
            startPoint: .top,
            endPoint: .center
        )
        .ignoresSafeArea()
        .animation(reduceMotion ? nil : Theme.artwork, value: tint)
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                    .frame(width: Theme.controlSize, height: Theme.controlSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close player")

            Spacer(minLength: 0)

            HStack(spacing: 7) {
                Rectangle()
                    .fill(accent)
                    .frame(width: 4, height: 4)
                    .accessibilityHidden(true)
                DotMatrixLabel(
                    text: "Now Playing",
                    color: Theme.secondaryText,
                    dotSize: 1.5
                )
            }

            Spacer(minLength: 0)

            if !player.queue.isEmpty {
                Menu {
                    Button("Queue", systemImage: "list.bullet") { isShowingQueue = true }
                    if let track = player.currentTrack, track.source.supportsDownloads {
                        Divider()
                        downloadAction(track)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .foregroundStyle(Theme.primaryText)
                        .frame(width: Theme.controlSize, height: Theme.controlSize)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("More actions")
            } else {
                Color.clear.frame(width: Theme.controlSize, height: Theme.controlSize)
            }
        }
        .padding(.horizontal, Theme.screenPadding)
    }

    private var albumCaption: String? {
        guard let album = player.currentTrack?.album, !album.isEmpty else { return nil }
        return album
    }

    private var queuePosition: String? {
        guard let index = player.queue.currentIndex, !player.queue.isEmpty else { return nil }
        return "\(index + 1)/\(player.queue.tracks.count)"
    }

    private var artwork: some View {
        TrackArtwork(
            track: player.currentTrack,
            localURL: model.artworkURL(for: player.currentTrack),
            cornerRadius: Theme.albumRadius
        )
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity)
        .overlay {
            RoundedRectangle(cornerRadius: Theme.albumRadius, style: .continuous)
                .stroke(Theme.border, lineWidth: Theme.hairline)
        }
        .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
        .scaleEffect(player.isPlaying || reduceMotion ? 1 : 0.96)
        .animation(reduceMotion ? nil : Theme.artwork, value: player.isPlaying)
        .padding(.top, 8)
    }

    private var titleBlock: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(player.currentTrack?.title ?? "Nothing playing")
                    .font(Theme.heroTitle)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                Text(player.currentTrack?.displayArtist ?? "")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                if let albumCaption {
                    TechnicalLabel(text: albumCaption)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let track = player.currentTrack {
                Button {
                    model.toggleFavorite(track)
                } label: {
                    Image(systemName: model.isFavorite(track) ? "heart.fill" : "heart")
                        .font(.title3)
                        .foregroundStyle(model.isFavorite(track) ? accent : Theme.primaryText)
                        .frame(width: Theme.controlSize, height: Theme.controlSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.isFavorite(track) ? "Remove from favorites" : "Add to favorites")
            }
        }
    }

    private func errorBlock(_ message: String) -> some View {
        VStack(spacing: 10) {
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
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.border, lineWidth: Theme.hairline)
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
                .frame(width: Theme.controlSize, height: Theme.controlSize)
                .frame(maxWidth: .infinity)
        }
    }

    private var repeatControl: some View {
        Button {
            player.cycleRepeatMode()
        } label: {
            Image(systemName: player.repeatMode.symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(player.repeatMode == .off ? Theme.secondaryText : accent)
                .frame(width: Theme.controlSize, height: Theme.controlSize)
                .overlay(alignment: .bottom) {
                    if player.repeatMode != .off {
                        Rectangle()
                            .fill(accent)
                            .frame(width: 5, height: 2)
                            .offset(y: -6)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(player.repeatMode.label)
    }

    private func lyricsControl(_ track: Track) -> some View {
        let available = track.lyricsQuery != nil
        return Button {
            isShowingLyrics = true
        } label: {
            actionIcon("quote.bubble", active: isShowingLyrics)
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .opacity(available ? 1 : 0.4)
        .accessibilityLabel("Lyrics")
        .accessibilityHint(
            available ? "Opens lyrics for this track" : "Lyrics need a track title and artist"
        )
    }

    // MARK: - Audio information

    private var audioInfoLine: some View {
        let variants = AudioInfoLine.variants(
            spec: audioSpec,
            source: audioSpec.source,
            isDownloaded: player.isCurrentFromDownload
        )
        return HStack(spacing: 10) {
            if let primary = variants.first {
                Button {
                    isShowingAudioSpec = true
                } label: {
                    // Most detailed first; ViewThatFits picks the first that fits
                    // on one line instead of truncating or wrapping.
                    ViewThatFits(in: .horizontal) {
                        chipRow(variants[min(0, variants.count - 1)])
                        chipRow(variants[min(1, variants.count - 1)])
                        chipRow(variants[min(2, variants.count - 1)])
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(primary.map(\.spokenText).joined(separator: ", "))
                .accessibilityHint("Shows audio details")
            }

            Spacer(minLength: 8)

            if let queuePosition {
                DotMatrixLabel(
                    text: queuePosition,
                    color: Theme.secondaryText,
                    dotSize: 1.4
                )
                .accessibilityLabel("Track \(queuePosition) in the queue")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chipRow(_ chips: [AudioInfoChip]) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                switch chip.kind {
                case .format, .status:
                    QualityBadgeLabel(text: chip.text, spokenText: chip.spokenText)
                case .detail:
                    TechnicalLabel(text: chip.text)
                }
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Actions

    private var actionRow: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.separator)
                .frame(height: Theme.hairline)
                .accessibilityHidden(true)

            HStack(spacing: 0) {
                if let track = player.currentTrack {
                    lyricsControl(track)
                }

                if !player.queue.isEmpty {
                    queueControl
                }

                if let track = player.currentTrack, track.source.supportsDownloads {
                    downloadControl(track)
                }

                #if canImport(AVKit)
                AirPlayRoutePicker()
                    .frame(maxWidth: .infinity, minHeight: Theme.controlSize)
                    .contentShape(Rectangle())
                #endif
            }
            .padding(.top, 4)
        }
    }

    private func actionIcon(_ name: String, active: Bool = false) -> some View {
        Image(systemName: name)
            .font(.body.weight(.semibold))
            .foregroundStyle(active ? accent : Theme.secondaryText)
            .frame(maxWidth: .infinity, minHeight: Theme.controlSize)
            .contentShape(Rectangle())
    }

    private var queueControl: some View {
        Button {
            isShowingQueue = true
        } label: {
            actionIcon("list.bullet")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Queue")
        .accessibilityValue(queuePosition.map { "Track \($0) in the queue" } ?? "")
        .accessibilityHint("Opens the queue")
    }

    private func downloadControl(_ track: Track) -> some View {
        let state = model.downloadState(for: track)
        return Button {
            switch state {
            case .completed:
                pendingDownloadRemoval = model.downloads.first {
                    $0.track.id == track.id && $0.state == .completed
                }
            case .failed, .cancelled, .none:
                model.startDownload(track)
            case .queued, .downloading:
                break
            }
        } label: {
            downloadIcon(state)
        }
        .buttonStyle(.plain)
        .disabled(state == .queued || isDownloading(state))
        .accessibilityLabel(downloadLabel(state))
        .accessibilityHint(downloadHint(state))
    }

    @ViewBuilder
    private func downloadIcon(_ state: DownloadState?) -> some View {
        switch state {
        case .queued?, .downloading?:
            ProgressView()
                .controlSize(.small)
                .tint(accent)
                .frame(maxWidth: .infinity, minHeight: Theme.controlSize)
        case .completed?:
            actionIcon("checkmark.circle.fill", active: true)
        case .failed?:
            actionIcon("arrow.clockwise")
        case .cancelled?, .none:
            actionIcon("arrow.down.circle")
        }
    }

    private func isDownloading(_ state: DownloadState?) -> Bool {
        if case .downloading = state { return true }
        return false
    }

    private func downloadLabel(_ state: DownloadState?) -> String {
        switch state {
        case .completed?: "Downloaded, remove download"
        case .queued?, .downloading?: "Downloading"
        case .failed?: "Retry download"
        case .cancelled?, .none: "Download"
        }
    }

    private func downloadHint(_ state: DownloadState?) -> String {
        switch state {
        case .completed?: "Removes the offline copy"
        case .queued?, .downloading?: "Download in progress"
        case .failed?: "Starts the download again"
        case .cancelled?, .none: "Keeps a copy for offline listening"
        }
    }
}
#endif
