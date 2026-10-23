// SettingsView.swift: appearance, sources, offline storage, playback and diagnostics.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

struct SettingsView: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var host = ""
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                header
                appearanceSection
                sourcesSection
                offlineSection
                cacheSection
                playbackSection
                aboutSection
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 6)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
                    .foregroundStyle(Theme.secondaryText)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.primaryText)
            }
        }
        .onAppear { host = model.streamingHost }
        .onChange(of: host) { _, _ in errorMessage = nil }
        .task {
            await model.refreshCacheSize()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                await model.refreshCacheSize()
            }
        }
        // The sheet has its own presentation environment; apply the authoritative
        // appearance here as well as at the root so an open sheet re-resolves now.
        .preferredColorScheme(model.appearanceMode.colorScheme)
        .tint(Theme.accent)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(Theme.accent)
                    .frame(width: Theme.sectionMarker, height: Theme.sectionMarker)
                    .accessibilityHidden(true)
                TechnicalLabel(text: "Monochrome / Settings")
            }
            Text("Settings")
                .font(Theme.screenTitle)
                .foregroundStyle(Theme.primaryText)
            Text("Appearance, sources and offline storage.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        settingsSection(
            "Appearance",
            meta: model.appearanceMode.title.uppercased(),
            footer: "System follows iOS. Light and Dark apply to this screen immediately and persist across launches."
        ) {
            settingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Interface")
                        .font(Theme.rowTitle)
                        .foregroundStyle(Theme.primaryText)
                    appearanceChoices
                }
                .padding(Theme.cardPadding)
            }
        }
    }

    private var appearanceChoices: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    ForEach(AppearanceMode.allCases) { mode in
                        appearanceButton(mode)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    ForEach(AppearanceMode.allCases) { mode in
                        appearanceButton(mode)
                    }
                }
            }
        }
        .animation(reduceMotion ? nil : Theme.quick, value: model.appearanceMode)
    }

    private func appearanceButton(_ mode: AppearanceMode) -> some View {
        let selected = model.appearanceMode == mode
        return Button {
            model.setAppearanceMode(mode)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: mode.symbolName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selected ? Theme.accent : Theme.primaryText)
                Text(mode.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(selected ? Theme.accent : Theme.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 64)
            .background(
                selected ? Theme.accentSurface : Theme.sunken,
                in: RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                    .stroke(selected ? Theme.accent : Theme.border, lineWidth: selected ? 1.5 : Theme.hairline)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Appearance \(mode.title)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Sources

    private var sourcesSection: some View {
        settingsSection(
            "Streaming sources",
            meta: "NETWORK",
            footer: "Only the Monochrome catalog and files you import can play. The catalog is a third-party relay; this app does not assume download rights or a YouTube Music integration."
        ) {
            settingsCard {
                settingsRow(
                    icon: "dot.radiowaves.left.and.right",
                    title: "Monochrome catalog",
                    detail: model.isStreamingConfigured
                        ? "Public FLAC catalog · \(hostName)"
                        : "Streaming is off; imported files still play."
                ) {
                    StatusBadge(text: model.isStreamingConfigured ? "On" : "Off", isActive: model.isStreamingConfigured)
                }
                settingsDivider()
                settingsRow(
                    icon: "waveform",
                    title: "Hi-Fi quality",
                    detail: "The catalog serves one lossless tier. Hi-Fi is a quality label, not a separate source."
                ) {
                    TechnicalLabel(text: "FLAC 16/44.1")
                }
                settingsDivider()
                settingsRow(
                    icon: "play.rectangle",
                    title: "YouTube Music",
                    detail: "No authorized integration is present in this build."
                ) {
                    StatusBadge(text: "Unavailable", isActive: false)
                }
            }

            settingsCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("CATALOG ENDPOINT")
                        .font(Theme.micro)
                        .tracking(1.0)
                        .foregroundStyle(Theme.tertiaryText)

                    HStack(spacing: 8) {
                        Image(systemName: "link")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.secondaryText)
                            .accessibilityHidden(true)
                        TextField("https://tracks.monochrome.st", text: $host)
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(Theme.primaryText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .submitLabel(.done)
                            .onSubmit { save() }
                            .accessibilityLabel("Catalog endpoint")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 11)
                    .background(
                        Theme.sunken,
                        in: RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                            .stroke(Theme.border, lineWidth: Theme.hairline)
                    }

                    HStack(spacing: 8) {
                        Button("Use default") {
                            host = StreamingSettings.defaultBaseURL.absoluteString
                            save()
                        }
                        .font(Theme.technical)
                        .foregroundStyle(Theme.secondaryText)
                        .frame(minHeight: 44)

                        Button("Turn off", role: .destructive) {
                            host = ""
                            save()
                        }
                        .font(Theme.technical)
                        .foregroundStyle(Theme.destructive)
                        .frame(minHeight: 44)

                        Spacer(minLength: 8)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Theme.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(Theme.cardPadding)
            }
        }
    }

    // MARK: - Offline music

    // No Download action is exposed: the catalog has no authorized download
    // entitlement (docs/ONLINE_STREAMING_AUDIT.md). Imported files are permanent.
    private var offlineSection: some View {
        settingsSection(
            "Offline music",
            meta: "PERMANENT",
            footer: "Permanent files are separate from the temporary cache. Imported files are never evicted by cache cleanup, and this build does not fake catalog downloads."
        ) {
            settingsCard {
                settingsRow(
                    icon: "internaldrive",
                    title: "Imported files",
                    detail: "Copied into app storage and always available offline."
                ) {
                    TechnicalLabel(text: localTrackCount == 1 ? "1 TRACK" : "\(localTrackCount) TRACKS")
                }
                settingsDivider()
                settingsRow(
                    icon: "arrow.down.circle",
                    title: "Catalog downloads",
                    detail: "Not available: the catalog has no authorized download API."
                ) {
                    StatusBadge(text: "Unavailable", isActive: false)
                }
            }
        }
    }

    // MARK: - Temporary cache

    private var cacheSection: some View {
        settingsSection(
            "Temporary cache",
            meta: "\(model.cacheEntryCount) OF \(AudioCache.defaultEntryLimit)",
            footer: "iOS may remove temporary files at any time. They are not permanent downloads, and permanent files are never part of this cache."
        ) {
            settingsCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: Theme.rowSpacing) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.primaryText)
                            .frame(width: Theme.iconSize, height: Theme.iconSize)
                            .background(
                                Theme.elevated,
                                in: RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                                    .stroke(Theme.border, lineWidth: Theme.hairline)
                            }
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Cached tracks")
                                .font(Theme.rowTitle)
                                .foregroundStyle(Theme.primaryText)
                            Text("Least recently used is removed first.")
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        Spacer(minLength: 8)
                        TechnicalLabel(text: byteText(model.cacheSizeBytes))
                    }

                    HStack(spacing: 4) {
                        ForEach(0..<AudioCache.defaultEntryLimit, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 1, style: .continuous)
                                .fill(index < model.cacheEntryCount ? Theme.accent : Theme.sunken)
                                .frame(height: 3)
                        }
                    }
                    .animation(reduceMotion ? nil : Theme.quick, value: model.cacheEntryCount)
                    .accessibilityHidden(true)
                }
                .padding(.horizontal, Theme.cardPadding)
                .padding(.vertical, 12)

                settingsDivider()
                settingsRow(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "Cache over cellular",
                    detail: "Off by default to protect mobile data."
                ) {
                    Toggle("Cache over cellular", isOn: Binding(
                        get: { model.allowsCellularCaching },
                        set: { model.setAllowsCellularCaching($0) }
                    ))
                    .labelsHidden()
                    .tint(Theme.accent)
                    .accessibilityLabel("Cache over cellular")
                }

                settingsDivider()
                settingsRow(
                    icon: "trash",
                    title: "Clear temporary cache",
                    detail: "\(model.cacheEntryCount == 1 ? "1 track" : "\(model.cacheEntryCount) tracks") · \(byteText(model.cacheSizeBytes))"
                ) {
                    Button("Clear", role: .destructive) {
                        Task { await model.clearCache() }
                    }
                    .font(Theme.technical)
                    .foregroundStyle(Theme.destructive)
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(model.cacheEntryCount == 0)
                    .opacity(model.cacheEntryCount == 0 ? 0.4 : 1)
                }
            }

            if model.cachedTracks.isEmpty {
                settingsCard {
                    Text("No temporary tracks")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(Theme.cardPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        TechnicalLabel(text: "Cached now")
                        Spacer(minLength: 8)
                        TechnicalLabel(text: "Most recent first")
                    }
                    .padding(.horizontal, 2)

                    settingsCard {
                        ForEach(Array(model.cachedTracks.enumerated()), id: \.element.id) { index, cached in
                            if index > 0 {
                                settingsDivider(inset: Theme.cardPadding)
                            }
                            cachedRow(cached)
                        }
                    }
                }
            }
        }
    }

    private func cachedRow(_ cached: CachedTrackSummary) -> some View {
        HStack(spacing: Theme.rowSpacing) {
            TrackArtwork(
                track: Track(
                    id: cached.trackID,
                    title: cached.title ?? "Cached song",
                    artist: cached.artist ?? "",
                    artworkURL: cached.artworkURL
                ),
                cornerRadius: Theme.artworkRadius
            )
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(cached.title ?? "Cached song")
                    .font(Theme.rowTitle)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                if let artist = cached.artist, !artist.isEmpty {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(byteText(cached.byteSize))
                    .font(Theme.time)
                    .foregroundStyle(Theme.secondaryText)
                Text(cached.lastUsedAt, style: .relative)
                    .font(Theme.micro)
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
            }

            Button(role: .destructive) {
                Task { await model.removeCachedTrack(cached) }
            } label: {
                Image(systemName: "trash")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.destructive)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(cached.title ?? "cached song") from the temporary cache")
        }
        .padding(.horizontal, Theme.cardPadding)
        .padding(.vertical, 8)
        .frame(minHeight: Theme.rowMinHeight)
    }

    // MARK: - Playback and connectivity

    private var playbackSection: some View {
        settingsSection(
            "Playback & connectivity",
            footer: "The app uses one playback engine and one playback audio session. Interruptions and route changes are handled by the system."
        ) {
            settingsCard {
                settingsRow(
                    icon: "lock",
                    title: "Lock Screen controls",
                    detail: "Play, pause, seek, next and previous from system media surfaces."
                ) {
                    StatusBadge(text: "On", isActive: true)
                }
                settingsDivider()
                settingsRow(
                    icon: "airplayaudio",
                    title: "AirPlay",
                    detail: "Choose a system audio route."
                ) {
                    #if canImport(AVKit)
                    AirPlayRoutePicker()
                        .frame(width: Theme.controlSize, height: Theme.controlSize)
                    #endif
                }
                settingsDivider()
                settingsRow(
                    icon: "hifispeaker",
                    title: "Background audio",
                    detail: "Playback continues when the screen locks."
                ) {
                    StatusBadge(text: "On", isActive: true)
                }
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        settingsSection(
            "About & diagnostics",
            meta: "BUILD",
            footer: "Monochrome is an independent native client. Catalog audio is relayed by a third party; no content rights are granted. No account, analytics or tracking SDK is included."
        ) {
            settingsCard {
                settingsRow(icon: "app.badge", title: "Version") {
                    TechnicalLabel(text: versionText)
                }
                settingsDivider()
                settingsRow(icon: "network", title: "Catalog") {
                    TechnicalLabel(text: hostName)
                }
                settingsDivider()
                settingsRow(icon: "clock.arrow.circlepath", title: "Cache policy") {
                    TechnicalLabel(text: "\(AudioCache.defaultEntryLimit) TRACKS · LRU")
                }
                settingsDivider()
                settingsRow(icon: "arrow.down.circle", title: "Permanent downloads") {
                    TechnicalLabel(text: "Unavailable")
                }
            }
        }
    }

    // MARK: - Building blocks

    private func settingsSection<Content: View>(
        _ title: String,
        meta: String? = nil,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Rectangle()
                    .fill(Theme.accent)
                    .frame(width: Theme.sectionMarker, height: 14)
                    .accessibilityHidden(true)
                Text(title)
                    .font(Theme.sectionTitle)
                    .foregroundStyle(Theme.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if let meta {
                    TechnicalLabel(text: meta)
                }
            }
            content()
            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }
        }
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            Theme.surface,
            in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.border, lineWidth: Theme.hairline)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private func settingsRow<Trailing: View>(
        icon: String,
        title: String,
        detail: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .center, spacing: Theme.rowSpacing) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .frame(width: Theme.iconSize, height: Theme.iconSize)
                .background(
                    Theme.elevated,
                    in: RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                        .stroke(Theme.border, lineWidth: Theme.hairline)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.rowTitle)
                    .foregroundStyle(Theme.primaryText)
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, Theme.cardPadding)
        .padding(.vertical, 10)
        .frame(minHeight: Theme.rowMinHeight)
    }

    private func settingsRow(icon: String, title: String, detail: String? = nil) -> some View {
        settingsRow(icon: icon, title: title, detail: detail) { EmptyView() }
    }

    private func settingsDivider(inset: CGFloat = Theme.cardPadding + Theme.iconSize + Theme.rowSpacing) -> some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: Theme.hairline)
            .padding(.leading, inset)
            .accessibilityHidden(true)
    }

    // MARK: - Actions and values

    private func save() {
        if model.saveStreamingHost(host) {
            errorMessage = nil
            dismiss()
        } else {
            errorMessage = "Enter an HTTPS address, for example https://tracks.monochrome.st."
        }
    }

    private var hostName: String {
        URL(string: model.streamingHost)?.host ?? "Not configured"
    }

    private var localTrackCount: Int {
        model.tracks.filter { !$0.isStreaming }.count
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }

    private func byteText(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

private struct StatusBadge: View {
    let text: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isActive ? Theme.accent : Theme.tertiaryText)
                .frame(width: 5, height: 5)
                .accessibilityHidden(true)
            Text(text.uppercased())
                .font(Theme.micro)
                .tracking(0.8)
                .foregroundStyle(isActive ? Theme.primaryText : Theme.tertiaryText)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            isActive ? Theme.accentSurface : Theme.sunken,
            in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

private extension AppearanceMode {
    var symbolName: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
}
#endif
