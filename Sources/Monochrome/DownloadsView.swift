// DownloadsView.swift: permanent offline files, separate from the temporary cache.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

struct DownloadsView: View {
    let model: AppModel

    @State private var pendingRemoval: DownloadItem?

    private var completed: [DownloadItem] { model.completedDownloads }
    private var active: [DownloadItem] {
        model.downloads.filter { $0.state != .completed }
    }

    var body: some View {
        List {
            if !active.isEmpty {
                Section("In progress") {
                    ForEach(active) { item in
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
                }
            }

            Section {
                ForEach(completed) { item in
                    Button {
                        guard let index = completed.firstIndex(where: { $0.id == item.id }) else { return }
                        Task {
                            await model.player.play(
                                tracks: completed.map(\.track),
                                startingAt: index
                            )
                        }
                    } label: {
                        TrackRow(
                            track: item.track,
                            isCurrent: model.player.currentTrack?.id == item.track.id,
                            showsDuration: true
                        )
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Remove", role: .destructive) {
                            pendingRemoval = item
                        }
                    }
                }
            } header: {
                if !completed.isEmpty {
                    Text("Downloaded")
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if completed.isEmpty && active.isEmpty {
                ContentUnavailableView {
                    Label("No downloads", systemImage: "arrow.down.circle")
                } description: {
                    Text("Download a song from its menu to keep it available offline.")
                }
            }
        }
        .task {
            await model.refreshDownloads()
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
            Button("Remove download", role: .destructive) {
                guard let item = pendingRemoval else { return }
                pendingRemoval = nil
                Task { await model.removeDownload(item) }
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("The offline copy is deleted. You can download it again later.")
        }
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
}
#endif
