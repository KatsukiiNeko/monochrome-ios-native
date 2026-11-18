// PlaylistImportView.swift: import progress, the review list and the save action.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

struct PlaylistImportView: View {
    let onFinished: () -> Void

    @Environment(PlaylistImportModel.self) private var importer
    @Environment(PlaylistModel.self) private var playlists
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accentColor) private var accent
    @State private var playlistName = ""

    var body: some View {
        NavigationStack {
            List {
                switch importer.phase {
                case .idle:
                    idleSection
                case .matching:
                    progressSection
                case .review:
                    reviewSection
                case .finished:
                    finishedSection
                }

                if let errorMessage = importer.errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.destructive)
                    }
                }
            }
            .listStyle(.plain)
            .listRowSeparatorTint(Theme.separator)
            .scrollContentBackground(.hidden)
        .contentMargins(.bottom, Theme.scrollBottomPadding, for: .scrollContent)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Import Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        importer.cancel()
                        dismiss()
                    }
                    .foregroundStyle(Theme.primaryText)
                }
            }
        }
        .presentationBackground(Theme.background)
        .tint(accent)
        .task {
            playlistName = importer.playlistName
        }
    }

    // MARK: - Sections

    private var idleSection: some View {
        Section {
            if importer.hasSavedProgress {
                Button {
                    importer.resume()
                    playlistName = importer.playlistName
                } label: {
                    Label("Continue last import", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, minHeight: Theme.controlSize)
                }
                .buttonStyle(.plain)
                .glassControlStyle()
                .accessibilityLabel("Continue the unfinished playlist import")
            }
        } footer: {
            Text("Pick a CSV, M3U, text or exported JSON file in the Playlists section.")
        }
    }

    private var progressSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                ProgressView(value: importer.progress)
                    .tint(accent)
                Text("\(importer.processedCount) of \(importer.totalCount) matched")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityLabel("\(importer.processedCount) of \(importer.totalCount) tracks matched")
                if importer.formatName.isEmpty == false {
                    TechnicalLabel(text: "\(importer.formatName) FILE")
                }
            }
            .padding(.vertical, 4)

            Button("Pause") { importer.pause() }
                .accessibilityLabel("Pause the import")
        }
    }

    private var reviewSection: some View {
        Section {
            if importer.reviewEntries.isEmpty {
                Text("Every entry was matched.")
                    .font(Theme.rowSubtitle)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                ForEach(importer.reviewEntries) { settlement in
                    reviewRow(settlement)
                }
            }
            TextField("Playlist name", text: $playlistName)
                .submitLabel(.done)
            Button {
                if importer.save(name: playlistName) {
                    onFinished()
                    dismiss()
                }
            } label: {
                Label("Save playlist", systemImage: "checkmark")
                    .frame(maxWidth: .infinity, minHeight: Theme.controlSize)
            }
            .buttonStyle(.plain)
            .glassControlStyle()
            .disabled(importer.matchedCount == 0)
            .opacity(importer.matchedCount == 0 ? 0.4 : 1)
            .accessibilityLabel("Save the imported playlist")
        } header: {
            TechnicalSectionHeader(
                title: "Needs Review",
                meta: "\(importer.reviewEntries.count)"
            )
        } footer: {
            Text(importer.summary)
        }
    }

    private func reviewRow(_ settlement: PlaylistImportSettlement) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(settlement.entry.artist) — \(settlement.entry.title)")
                .font(Theme.rowTitle)
                .foregroundStyle(Theme.primaryText)
                .lineLimit(2)
            if settlement.reviewCandidates.isEmpty {
                Text("No close match found")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                ForEach(settlement.reviewCandidates) { candidate in
                    Button {
                        importer.choose(settlement, track: candidate)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.right.circle")
                                .foregroundStyle(accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.title)
                                    .font(Theme.rowSubtitle)
                                    .foregroundStyle(Theme.primaryText)
                                Text(candidate.displayArtist)
                                    .font(Theme.caption)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            Spacer(minLength: 4)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Use \(candidate.title) by \(candidate.displayArtist)")
                }
            }
            Button("Skip this track", role: .destructive) {
                importer.reject(settlement)
            }
            .font(Theme.caption)
            .accessibilityLabel("Skip \(settlement.entry.title)")
        }
        .padding(.vertical, 4)
    }

    private var finishedSection: some View {
        Section {
            Text("The playlist was saved.")
                .font(Theme.rowSubtitle)
                .foregroundStyle(Theme.secondaryText)
            Button("Done") {
                onFinished()
                dismiss()
            }
            .accessibilityLabel("Close the import")
        }
    }
}
#endif
