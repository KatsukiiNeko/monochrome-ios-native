// PlaylistsSection.swift: the Library section that lists and opens playlists.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

struct PlaylistsSection: View {
    let model: AppModel
    var onCreate: () -> Void

    @Environment(PlaylistModel.self) private var playlists
    @Environment(PlaylistImportModel.self) private var importer
    @Environment(\.accentColor) private var accent
    @State private var isImporting = false
    @State private var isPickingFile = false

    var body: some View {
        Section {
            ForEach(playlists.playlists) { playlist in
                NavigationLink {
                    PlaylistDetailView(model: model, playlistID: playlist.id)
                } label: {
                    row(playlist)
                }
                .accessibilityLabel(
                    "\(playlist.name), \(songCount(playlist.items.count))"
                )
                .accessibilityHint("Opens the playlist")
            }

            Button {
                onCreate()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(accent)
                        .frame(width: 40, height: 40)
                        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: Theme.tileRadius))
                    Text("New playlist")
                        .font(Theme.listRowTitle)
                        .foregroundStyle(Theme.primaryText)
                    Spacer(minLength: 8)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("New playlist")
                .accessibilityHint("Names and creates a playlist")
            }
            .buttonStyle(.plain)

            Button {
                isPickingFile = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(accent)
                        .frame(width: 40, height: 40)
                        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: Theme.tileRadius))
                    Text("Import playlist")
                        .font(Theme.listRowTitle)
                        .foregroundStyle(Theme.primaryText)
                    Spacer(minLength: 8)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Import playlist from a file")
                .accessibilityHint("Reads a CSV, M3U, text or exported JSON file")
            }
            .buttonStyle(.plain)
        } header: {
            TechnicalSectionHeader(
                title: "Playlists",
                meta: playlists.playlists.isEmpty ? "NONE" : "\(playlists.playlists.count)"
            )
        }
        .fileImporter(
            isPresented: $isPickingFile,
            allowedContentTypes: [.commaSeparatedText, .plainText, .json, .audio],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            importer.start(fileURL: url)
            isImporting = true
        }
        .sheet(isPresented: $isImporting) {
            PlaylistImportView {}
                .environment(importer)
                .environment(playlists)
        }
    }

    private func row(_ playlist: Playlist) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note.list")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 40, height: 40)
                .background(Theme.elevated, in: RoundedRectangle(cornerRadius: Theme.tileRadius))

            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(Theme.listRowTitle)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                TechnicalLabel(text: songCount(playlist.items.count))
            }

            Spacer(minLength: 8)
        }
    }

    private func songCount(_ count: Int) -> String {
        count == 1 ? "1 song" : "\(count) songs"
    }
}
#endif
