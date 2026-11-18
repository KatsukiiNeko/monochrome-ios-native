// PodcastsView.swift: search the podcast directory and play an episode.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

struct PodcastsView: View {
    let model: AppModel

    @Environment(PodcastModel.self) private var podcasts
    @Environment(\.accentColor) private var accent
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                searchField
                if podcasts.isSearching {
                    ProgressView()
                        .tint(accent)
                        .accessibilityLabel("Searching podcast shows")
                }
                if let errorMessage = podcasts.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.rowSubtitle)
                        .foregroundStyle(Theme.destructive)
                }
                ForEach(podcasts.shows) { show in
                    NavigationLink {
                        PodcastShowView(model: model, show: show)
                    } label: {
                        showRow(show)
                    }
                    .buttonStyle(.plain)
                }
                if podcasts.shows.isEmpty, !podcasts.isSearching, podcasts.query.count >= 2,
                   podcasts.errorMessage == nil {
                    Text("No shows found.")
                        .font(Theme.rowSubtitle)
                        .foregroundStyle(Theme.secondaryText)
                }
                if podcasts.query.count < 2 {
                    Text("Search for a show by name, host or topic.")
                        .font(Theme.rowSubtitle)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.vertical, 8)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Podcasts")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: podcasts.query) { await podcasts.search() }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(isSearchFocused ? accent : Theme.secondaryText)
            TextField("Podcast shows", text: Binding(
                get: { podcasts.query },
                set: { podcasts.query = $0 }
            ))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .focused($isSearchFocused)
            .tint(accent)
            .accessibilityLabel("Search podcast shows")
            if !podcasts.query.isEmpty {
                Button {
                    podcasts.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.tertiaryText)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(isSearchFocused ? accent : Theme.border, lineWidth: Theme.hairline)
        }
    }

    private func showRow(_ show: RemotePodcast) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: show.artworkURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Rectangle().fill(Theme.elevated)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: Theme.albumRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(show.title)
                    .font(Theme.rowTitle)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(2)
                Text(show.author)
                    .font(Theme.rowSubtitle)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                if let genre = show.genre {
                    TechnicalLabel(text: genre.uppercased())
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the show")
    }
}

struct PodcastShowView: View {
    let model: AppModel
    let show: RemotePodcast

    @Environment(PodcastModel.self) private var podcasts
    @Environment(\.accentColor) private var accent

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    AsyncImage(url: show.artworkURL) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Rectangle().fill(Theme.elevated)
                        }
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.albumRadius, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(show.title)
                            .font(Theme.rowTitle)
                            .foregroundStyle(Theme.primaryText)
                        Text(show.author)
                            .font(Theme.rowSubtitle)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                if podcasts.isLoadingEpisodes {
                    ProgressView()
                        .tint(accent)
                        .accessibilityLabel("Loading episodes")
                } else if let errorMessage = podcasts.errorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.destructive)
                        Button("Retry") {
                            Task { await podcasts.open(show) }
                        }
                        .font(Theme.technical)
                    }
                } else if podcasts.episodes.isEmpty {
                    Text("This show lists no episodes.")
                        .font(Theme.rowSubtitle)
                        .foregroundStyle(Theme.secondaryText)
                }
                ForEach(podcasts.episodes) { episode in
                    Button {
                        podcasts.play(episode)
                    } label: {
                        episodeRow(episode)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                TechnicalSectionHeader(
                    title: "Episodes",
                    meta: podcasts.episodes.isEmpty ? nil : "\(podcasts.episodes.count)"
                )
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, Theme.scrollBottomPadding, for: .scrollContent)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(show.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard podcasts.selectedShow != show || podcasts.episodes.isEmpty else { return }
            await podcasts.open(show)
        }
    }

    private func episodeRow(_ episode: PodcastEpisode) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(episode.title)
                .font(Theme.rowTitle)
                .foregroundStyle(
                    model.player.currentTrack?.id == "podcast:\(episode.id)"
                        ? accent
                        : Theme.primaryText
                )
                .lineLimit(2)
            HStack(spacing: 6) {
                if let publishedAt = episode.publishedAt {
                    Text(publishedAt.formatted(date: .abbreviated, time: .omitted))
                }
                if let duration = episode.durationSeconds {
                    Text(formatDuration(duration))
                }
            }
            .font(Theme.caption)
            .foregroundStyle(Theme.secondaryText)
            if let summary = episode.summary {
                Text(summary)
                    .font(Theme.rowSubtitle)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Plays this episode")
    }
}
#endif
