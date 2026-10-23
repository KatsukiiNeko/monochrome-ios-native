// DownloadsView.swift: permanent offline files, separate from the temporary cache.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

struct DownloadsView: View {
    let model: AppModel

    @State private var pendingRemoval: DownloadItem?
    @State private var failureMessage: String?
    @State private var hasLoaded = false

    private var completed: [DownloadItem] { model.completedDownloads }
    private var active: [DownloadItem] {
        model.downloads.filter { $0.state != .completed }
    }

    var body: some View {
        List {
            if let metadataError = model.downloadsMetadataError {
                Section {
                    Label(metadataError, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.destructive)
                } footer: {
                    Text("Stored audio was left untouched. Downloads are unavailable until the records file is repaired.")
                }
            }

            if let failureMessage {
                Section {
                    Label(failureMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.destructive)
                }
            }

            if !active.isEmpty {
                Section("In Progress") {
                    ForEach(active) { item in
                        activeRow(item)
                    }
                }
            }

            Section {
                ForEach(completed) { item in
                    completedRow(item)
                }
            } header: {
                if !completed.isEmpty {
                    HStack {
                        Text("Downloaded")
                        Spacer()
                        Text(byteText(model.downloadsBytes))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if completed.isEmpty, active.isEmpty, model.downloadsMetadataError == nil {
                if !hasLoaded || model.isRefreshingDownloads {
                    ProgressView("Loading downloads…")
                } else {
                    ContentUnavailableView {
                        Label("No downloads", systemImage: "arrow.down.circle")
                    } description: {
                        Text("Download a song from its menu to keep it available offline.")
                    }
                }
            }
        }
        .task {
            await model.refreshDownloads()
            hasLoaded = true
            while !Task.isCancelled {
                guard model.downloads.contains(where: { $0.state != .completed }) else { break }
                try? await Task.sleep(for: .milliseconds(500))
                await model.refreshDownloads()
            }
        }
        .confirmationDialog(
            "Remove “\(pendingRemoval?.track.title ?? "this download")”?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove Download", role: .destructive) {
                guard let item = pendingRemoval else { return }
                pendingRemoval = nil
                Task {
                    if await model.removeDownload(item) {
                        failureMessage = nil
                    } else {
                        failureMessage = model.errorMessage ?? "The download could not be removed."
                    }
                }
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("The offline copy is deleted. You can download it again later.")
        }
        .preferredColorScheme(model.appearanceMode.colorScheme)
        .tint(Theme.accent)
    }

    private func completedRow(_ item: DownloadItem) -> some View {
        Button {
            guard let index = completed.firstIndex(where: { $0.id == item.id }) else { return }
            Task {
                await model.player.play(
                    tracks: completed.map(\.track),
                    startingAt: index
                )
            }
        } label: {
            HStack(spacing: 8) {
                TrackRow(
                    track: item.track,
                    isCurrent: model.player.currentTrack?.id == item.track.id,
                    showsDuration: false
                )
                Text(byteText(item.record?.byteSize ?? 0))
                    .font(Theme.time)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .swipeActions {
            Button("Remove", role: .destructive) {
                pendingRemoval = item
            }
        }
        .accessibilityHint("Plays this downloaded track")
    }

    private func activeRow(_ item: DownloadItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: Theme.rowSpacing) {
                TrackRow(track: item.track, showsDuration: false)
                Spacer(minLength: 8)
                TechnicalLabel(text: stateText(item.state))
            }
            if case .downloading(let progress) = item.state {
                if let progress {
                    ProgressView(value: progress)
                        .tint(Theme.accent)
                } else {
                    ProgressView()
                        .tint(Theme.accent)
                }
            }
            if case .failed(let reason) = item.state {
                Text(reason)
                    .font(Theme.rowSubtitle)
                    .foregroundStyle(Theme.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Retry") {
                    model.startDownload(item.track)
                }
                .font(Theme.technical)
                .foregroundStyle(Theme.accent)
            }
        }
        .padding(.vertical, 4)
    }

    private func stateText(_ state: DownloadState) -> String {
        switch state {
        case .queued: "QUEUED"
        case .downloading: "DOWNLOADING"
        case .completed: "DONE"
        case .failed: "FAILED"
        case .cancelled: "CANCELLED"
        }
    }

    private func byteText(_ bytes: Int) -> String {
        guard bytes > 0 else { return "0 bytes" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
#endif
