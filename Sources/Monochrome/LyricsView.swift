// LyricsView.swift: on-demand synced or plain lyrics for the current track.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

struct LyricsView: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accentColor) private var accent
    @State private var state: LoadState = .loading
    @State private var follow = true
    @State private var timingDelay: TimeInterval = 0

    private static let timingStep: TimeInterval = 0.25
    private static let maxTimingDelay: TimeInterval = 5

    private var player: PlayerController { model.player }
    private var track: Track? { player.currentTrack }
    private var query: LyricsQuery? { track?.lyricsQuery }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Lyrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    timingControl
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.primaryText)
                }
            }
            .tint(accent)
        }
        .task(id: track?.id) {
            loadTimingDelay()
            await load()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(track?.title ?? "Nothing playing")
                .font(Theme.listRowTitle)
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
            Text(track?.displayArtist ?? "")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.screenPadding)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            loadingView
        case .missingMetadata:
            stateView(
                title: "Lyrics unavailable",
                message: "Lyrics need a track title and artist.",
                retry: nil
            )
        case .offline:
            stateView(
                title: "Offline",
                message: "Lyrics are not available offline.",
                retry: { Task { await load(refreshing: true) } }
            )
        case .failed(let message):
            stateView(
                title: "Could not load lyrics",
                message: message,
                retry: { Task { await load(refreshing: true) } }
            )
        case .content(let result):
            switch result.content {
            case .synced(let lines):
                if lines.isEmpty {
                    notFoundView
                } else {
                    syncedView(lines: lines, source: result.source)
                }
            case .plain(let text):
                plainView(text: text, source: result.source)
            case .instrumental:
                stateView(
                    title: "Instrumental",
                    message: "This track has no lyrics.",
                    retry: nil
                )
            case .notFound:
                notFoundView
            }
        }
    }

    // MARK: - Content

    private func syncedView(lines: [LyricLine], source: String) -> some View {
        let active = activeIndex(in: lines)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        Button {
                            player.seek(to: line.time)
                        } label: {
                            Text(line.text.isEmpty ? " " : line.text)
                                .font(.title3.weight(index == active ? .semibold : .regular))
                                .foregroundStyle(index == active ? Theme.primaryText : Theme.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(index)
                        .accessibilityLabel(line.text.isEmpty ? "Musical gap" : line.text)
                        .accessibilityHint("Seeks to this line")
                        .accessibilityAddTraits(index == active ? .isSelected : [])
                    }
                    sourceFooter(source)
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.vertical, 24)
            }
            .onAppear {
                if let active { proxy.scrollTo(active, anchor: .center) }
            }
            .onChange(of: active) { _, newValue in
                guard follow, let newValue else { return }
                scroll(proxy, to: newValue)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 8).onChanged { _ in
                    if follow { follow = false }
                }
            )
            .overlay(alignment: .bottomTrailing) {
                if !follow, active != nil {
                    followButton(proxy, active: active)
                        .padding(Theme.screenPadding)
                }
            }
        }
    }

    private func plainView(text: String, source: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(text)
                    .font(.body)
                    .lineSpacing(6)
                    .foregroundStyle(Theme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                sourceFooter(source)
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.vertical, 24)
        }
    }

    private var notFoundView: some View {
        stateView(
            title: "No lyrics found",
            message: "This track is not in the lyrics database.",
            retry: { Task { await load(refreshing: true) } }
        )
    }

    private var loadingView: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(0..<6, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Theme.surface)
                    .frame(width: index.isMultiple(of: 2) ? 260 : 190, height: 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.screenPadding)
        .padding(.top, 32)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading lyrics")
    }

    private func stateView(title: String, message: String, retry: (() -> Void)?) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "quote.bubble")
                .font(.title3)
                .foregroundStyle(Theme.secondaryText)
                .accessibilityHidden(true)
            Text(title)
                .font(Theme.listRowTitle)
                .foregroundStyle(Theme.primaryText)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            if let retry {
                Button("Retry", action: retry)
                    .glassControlStyle()
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.border, lineWidth: Theme.hairline)
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.top, 24)
    }

    private func sourceFooter(_ source: String) -> some View {
        Text("Lyrics from \(source)")
            .font(.caption2)
            .foregroundStyle(Theme.tertiaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
    }

    private func activeIndex(in lines: [LyricLine]) -> Int? {
        LyricsTimeline.activeIndex(
            in: lines,
            position: player.position,
            offset: -timingDelay
        )
    }

    // MARK: - Timing

    @ViewBuilder
    private var timingControl: some View {
        if case .content(let result) = state,
           case .synced(let lines) = result.content,
           !lines.isEmpty {
            Menu {
                Button("Earlier by 0.25 seconds", systemImage: "minus") {
                    setTimingDelay(timingDelay - Self.timingStep)
                }
                Button("Later by 0.25 seconds", systemImage: "plus") {
                    setTimingDelay(timingDelay + Self.timingStep)
                }
                if timingDelay != 0 {
                    Divider()
                    Button("Reset timing", systemImage: "arrow.counterclockwise") {
                        setTimingDelay(0)
                    }
                }
            } label: {
                Image(systemName: "timer")
            }
            .accessibilityLabel("Lyrics timing")
            .accessibilityValue(timingDescription)
        }
    }

    private var timingDescription: String {
        let value = abs(timingDelay)
        guard value > 0 else { return "In sync" }
        let text = value == value.rounded()
            ? String(Int(value))
            : String(format: "%g", value)
        return timingDelay > 0 ? "\(text) seconds later" : "\(text) seconds earlier"
    }

    private var timingKey: String {
        "lyrics.timingDelay.\(track?.id ?? "none")"
    }

    private func loadTimingDelay() {
        let stored = UserDefaults.standard.double(forKey: timingKey)
        timingDelay = min(max(stored, -Self.maxTimingDelay), Self.maxTimingDelay)
    }

    private func setTimingDelay(_ value: TimeInterval) {
        let clamped = min(max(value, -Self.maxTimingDelay), Self.maxTimingDelay)
        timingDelay = clamped
        if clamped == 0 {
            UserDefaults.standard.removeObject(forKey: timingKey)
        } else {
            UserDefaults.standard.set(clamped, forKey: timingKey)
        }
    }

    private func followButton(_ proxy: ScrollViewProxy, active: Int?) -> some View {
        Button {
            follow = true
            if let active { scroll(proxy, to: active) }
        } label: {
            Label("Follow", systemImage: "arrow.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.surface, in: Capsule())
                .overlay {
                    Capsule().stroke(accent.opacity(0.6), lineWidth: Theme.hairline)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Follow the current line")
    }

    private func scroll(_ proxy: ScrollViewProxy, to index: Int) {
        if reduceMotion {
            proxy.scrollTo(index, anchor: .center)
        } else {
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(index, anchor: .center)
            }
        }
    }

    // MARK: - Loading

    private func load(refreshing: Bool = false) async {
        guard let query, query.isQueryable else {
            state = .missingMetadata
            return
        }
        let trackID = track?.id
        state = .loading
        follow = true
        do {
            let result = try await model.lyricsService.load(query, refreshing: refreshing)
            guard !Task.isCancelled, player.currentTrack?.id == trackID else { return }
            state = .content(result)
        } catch is CancellationError {
            return
        } catch let error as LyricsLoadError {
            guard !Task.isCancelled, player.currentTrack?.id == trackID else { return }
            if error == .offline {
                state = .offline
            } else {
                state = .failed(error.localizedDescription)
            }
        } catch {
            guard !Task.isCancelled, player.currentTrack?.id == trackID else { return }
            state = .failed(LyricsLoadError.unavailable.localizedDescription)
        }
    }

    private enum LoadState: Equatable {
        case loading
        case missingMetadata
        case offline
        case failed(String)
        case content(LyricsResult)
    }
}
#endif
