// SettingsView.swift: grouped preferences, catalog control and storage entries.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @State private var clearedCache = false
    @State private var isConfirmingEndpointReset = false

    var body: some View {
        List {
            appearanceSection
            streamingSection
            cacheSection
            downloadsSection
            aboutSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .listRowBackground(Theme.surface)
        .listRowSeparatorTint(Theme.separator)
        .background(Theme.background.ignoresSafeArea())
        .environment(\.accentColor, accent)
        .environment(\.onAccentColor, onAccent)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.primaryText)
            }
        }
        // The sheet has its own presentation environment; apply the authoritative
        // appearance here as well as at the root so an open sheet re-resolves now.
        .preferredColorScheme(model.appearanceMode.colorScheme)
        .tint(accent)
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section {
            Picker(
                "Theme",
                selection: Binding(
                    get: { model.appearanceMode },
                    set: { model.setAppearanceMode($0) }
                )
            ) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .tint(accent)
            .accessibilityLabel("Appearance")

            accentChoices

            NavigationLink {
                ThemePickerView(model: model)
            } label: {
                settingsLabel(icon: "paintpalette", title: "Theme", value: model.theme.name)
            }
        } header: {
            TechnicalSectionHeader(title: "Appearance")
        }
    }

    private var accentChoices: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(AccentPreference.allCases.filter { $0 != .artwork }) { preference in
                        accentSwatch(preference)
                    }
                }
            }

            Button {
                model.setAccentPreference(.artwork)
            } label: {
                HStack(spacing: 10) {
                    Circle()
                        .fill(Theme.accentColor(preference: .artwork, artwork: model.artworkAccent))
                        .frame(width: 22, height: 22)
                        .overlay {
                            Circle().stroke(Theme.border, lineWidth: Theme.hairline)
                        }
                    Text("Match Artwork")
                        .font(Theme.listRowTitle)
                        .foregroundStyle(Theme.primaryText)
                    Spacer(minLength: 8)
                    if model.accentPreference == .artwork {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(accent)
                    }
                }
                .frame(minHeight: Theme.rowMinHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Accent color: Match artwork")
            .accessibilityAddTraits(model.accentPreference == .artwork ? .isSelected : [])
        }
        .padding(.top, 4)
    }

    private func accentSwatch(_ preference: AccentPreference) -> some View {
        let selected = model.accentPreference == preference
        return Button {
            model.setAccentPreference(preference)
        } label: {
            Circle()
                .fill(Theme.accentColor(preference: preference, artwork: nil))
                .frame(width: 30, height: 30)
                .overlay {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(
                                Theme.onAccentColor(preference: preference, artwork: nil)
                            )
                    }
                }
                .overlay {
                    Circle()
                        .stroke(Theme.primaryText, lineWidth: selected ? 2 : 0)
                        .padding(-4)
                }
                .frame(width: 38, height: 38)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Accent color: \(preference.title)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Streaming endpoint

    private var streamingSection: some View {
        Section {
            Toggle(
                isOn: Binding(
                    get: { model.isMonochromeEnabled },
                    set: { model.setMonochromeEnabled($0) }
                )
            ) {
                settingsLabel(icon: "dot.radiowaves.left.and.right", title: "Enable Endpoint")
            }
            .tint(accent)

            NavigationLink {
                StreamingEndpointView(model: model)
            } label: {
                settingsLabel(icon: "link", title: "Catalog Endpoint", value: endpointValue)
            }

            NavigationLink {
                CatalogHostsView(model: model)
            } label: {
                settingsLabel(icon: "server.rack", title: "Catalog Hosts", value: hostsValue)
            }

            Button(role: .destructive) {
                if model.hasCustomStreamingEndpoint {
                    isConfirmingEndpointReset = true
                } else {
                    model.resetStreamingEndpoint()
                }
            } label: {
                settingsLabel(
                    icon: "arrow.counterclockwise",
                    title: "Reset Endpoint",
                    destructive: true
                )
            }
            .confirmationDialog(
                "Reset the catalog endpoint?",
                isPresented: $isConfirmingEndpointReset,
                titleVisibility: .visible
            ) {
                Button("Reset Endpoint", role: .destructive) {
                    model.resetStreamingEndpoint()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The custom address is replaced with \(StreamingSettings.defaultBaseURL.absoluteString).")
            }

            if let error = model.streamingSettingsError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.destructive)
            }
        } header: {
            TechnicalSectionHeader(title: "Streaming Endpoint")
        } footer: {
            Text("Monochrome supplies the online catalog and streaming. Local files and downloads stay available when it is off.")
        }
    }

    // MARK: - Cache

    private var cacheSection: some View {
        Section {
            Button(role: .destructive) {
                Task {
                    await model.clearCache()
                    clearedCache = true
                    try? await Task.sleep(for: .seconds(1.5))
                    clearedCache = false
                }
            } label: {
                settingsLabel(
                    icon: clearedCache ? "checkmark" : "trash",
                    title: clearedCache ? "Cleared" : "Clear Cache",
                    destructive: !clearedCache
                )
            }
            .accessibilityLabel(clearedCache ? "Cache cleared" : "Clear Cache")
        } header: {
            TechnicalSectionHeader(title: "Cache")
        }
    }

    // MARK: - Downloads

    private var downloadsSection: some View {
        Section {
            NavigationLink {
                DownloadsView(model: model)
            } label: {
                settingsLabel(icon: "arrow.down.circle", title: "Manage Downloads", value: downloadsValue)
            }
        } header: {
            TechnicalSectionHeader(title: "Downloads")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            NavigationLink {
                AboutView(model: model)
            } label: {
                settingsLabel(icon: "info.circle", title: "About Monochrome")
            }
        } header: {
            TechnicalSectionHeader(title: "About")
        }
    }

    // MARK: - Row building blocks

    private func settingsLabel(
        icon: String,
        title: String,
        value: String? = nil,
        destructive: Bool = false
    ) -> some View {
        HStack(spacing: 10) {
            TechnicalIcon(name: icon, destructive: destructive)
            Text(title)
                .font(Theme.listRowTitle)
                .foregroundStyle(destructive ? Theme.destructive : Theme.primaryText)
            Spacer(minLength: 8)
            if let value {
                TechnicalLabel(text: value, color: Theme.secondaryText)
            }
        }
        .frame(minHeight: Theme.rowMinHeight)
    }

    // MARK: - Actions and values

    private var accent: Color {
        Theme.accentColor(preference: model.accentPreference, artwork: model.artworkAccent)
    }

    private var onAccent: Color {
        Theme.onAccentColor(preference: model.accentPreference, artwork: model.artworkAccent)
    }

    private var endpointValue: String {
        guard let host = URL(string: model.streamingHost)?.host, !host.isEmpty else { return "Not set" }
        return host
    }

    private var downloadsValue: String {
        let count = model.completedDownloads.count
        return count == 1 ? "1 song" : "\(count) songs"
    }

    private var hostsValue: String {
        model.userHosts.isEmpty ? "Default only" : "\(model.userHosts.count) extra"
    }
}

// MARK: - Theme picker

private struct ThemePickerView: View {
    let model: AppModel

    @Environment(\.accentColor) private var accent
    @State private var isImporting = false
    @State private var exportURL: URL?
    @State private var message: String?

    var body: some View {
        List {
            Section {
                ForEach(model.themePresets) { preset in
                    Button {
                        model.selectTheme(id: preset.id)
                    } label: {
                        row(preset)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Theme: \(preset.name)")
                    .accessibilityAddTraits(model.theme.id == preset.id ? .isSelected : [])
                }
            } header: {
                TechnicalSectionHeader(title: "Presets")
            } footer: {
                Text("OLED Black turns the background fully black in dark appearance.")
            }

            Section {
                Button("Import Theme…", systemImage: "square.and.arrow.down") {
                    isImporting = true
                }
                .foregroundStyle(Theme.primaryText)

                if let exportURL {
                    ShareLink(item: exportURL) {
                        Text("Export Current Theme")
                            .foregroundStyle(Theme.primaryText)
                    }
                }
            } header: {
                TechnicalSectionHeader(title: "Files")
            } footer: {
                Text(
                    message
                        ?? "Themes are JSON files. An imported theme must keep primary text at 4.5:1 or better in both appearances."
                )
                .foregroundStyle(message == nil ? Theme.secondaryText : Theme.destructive)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .listRowBackground(Theme.surface)
        .listRowSeparatorTint(Theme.separator)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Theme")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    message = model.importTheme(from: data)
                    if message == nil { prepareExport() }
                } catch {
                    message = error.localizedDescription
                }
            case .failure(let error):
                message = error.localizedDescription
            }
        }
        .onAppear { prepareExport() }
        .onChange(of: model.theme) { _, _ in prepareExport() }
        .preferredColorScheme(model.appearanceMode.colorScheme)
        .tint(accent)
    }

    private func row(_ preset: ThemeDefinition) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                swatch(preset.light.background.paletteColor, text: preset.light.primaryText.paletteColor)
                swatch(preset.dark.background.paletteColor, text: preset.dark.primaryText.paletteColor)
            }
            .frame(width: 52, height: 26)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Theme.border, lineWidth: Theme.hairline)
            }
            .accessibilityHidden(true)

            Text(preset.name)
                .font(Theme.listRowTitle)
                .foregroundStyle(Theme.primaryText)

            Spacer(minLength: 8)

            if model.theme.id == preset.id {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent)
            }
        }
        .frame(minHeight: Theme.rowMinHeight)
        .contentShape(Rectangle())
    }

    private func swatch(_ background: PaletteColor, text: PaletteColor) -> some View {
        ZStack {
            Rectangle().fill(Color(background))
            Circle()
                .fill(Color(text))
                .frame(width: 6, height: 6)
        }
    }

    /// Writes the current theme beside the app so the share sheet has a real file.
    private func prepareExport() {
        guard let data = model.exportCurrentTheme() else {
            exportURL = nil
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("monochrome-theme.json")
        do {
            try data.write(to: url, options: .atomic)
            exportURL = url
        } catch {
            exportURL = nil
            message = "The theme could not be prepared for export."
        }
    }
}

// MARK: - Extra catalog hosts

/// User-managed failover hosts. The list is ordered: these are tried first, then
/// the endpoint above and finally the built-in default.
private struct CatalogHostsView: View {
    let model: AppModel

    @Environment(\.accentColor) private var accent
    @State private var host = ""
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                ForEach(model.userHosts, id: \.absoluteString) { url in
                    Text(url.host ?? url.absoluteString)
                        .font(Theme.listRowTitle)
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                }
                .onMove { offsets, destination in
                    guard let source = offsets.first else { return }
                    model.moveStreamingHost(from: source, to: destination)
                }
                .onDelete { offsets in
                    for index in offsets.sorted(by: >) {
                        model.removeStreamingHost(at: index)
                    }
                }

                if model.userHosts.isEmpty {
                    Text("Only the built-in host is used.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            } header: {
                TechnicalSectionHeader(
                    title: "Additional Hosts",
                    meta: "\(model.userHosts.count)/\(StreamingSettings.maximumUserHosts)"
                )
            } footer: {
                Text(
                    errorMessage
                        ?? "Tried in this order, then the endpoint above. HTTPS only. Swipe a host to remove it and use Edit to reorder."
                )
                .foregroundStyle(errorMessage == nil ? Theme.secondaryText : Theme.destructive)
            }

            Section {
                TextField("https://example.com", text: $host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.done)
                    .onSubmit(add)
                    .onChange(of: host) { _, _ in errorMessage = nil }
                    .accessibilityLabel("New catalog host")

                Button("Add Host") { add() }
                    .foregroundStyle(Theme.primaryText)

                Button(role: .destructive) {
                    model.resetStreamingHosts()
                    errorMessage = nil
                } label: {
                    Text("Reset Hosts")
                        .foregroundStyle(Theme.destructive)
                }
            } header: {
                TechnicalSectionHeader(title: "Add")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .listRowBackground(Theme.surface)
        .listRowSeparatorTint(Theme.separator)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Catalog Hosts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.userHosts.count > 1 {
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
        }
        .preferredColorScheme(model.appearanceMode.colorScheme)
        .tint(accent)
    }

    private func add() {
        if model.addStreamingHost(host) {
            host = ""
            errorMessage = nil
        } else {
            errorMessage = "Enter a new HTTPS address. Hosts are limited to \(StreamingSettings.maximumUserHosts)."
        }
    }
}

// MARK: - Catalog endpoint

private struct StreamingEndpointView: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accentColor) private var accent
    @State private var host = ""
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                TextField(StreamingSettings.defaultBaseURL.absoluteString, text: $host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.done)
                    .onSubmit(save)
                    .onChange(of: host) { _, _ in errorMessage = nil }
                    .accessibilityLabel("Catalog endpoint")
            } header: {
                TechnicalSectionHeader(title: "Address")
            } footer: {
                Text(
                    errorMessage
                        ?? "HTTPS only. The built-in endpoint is \(StreamingSettings.defaultBaseURL.absoluteString)."
                )
                .foregroundStyle(errorMessage == nil ? Theme.secondaryText : Theme.destructive)
            }

            Section {
                Button {
                    host = StreamingSettings.defaultBaseURL.absoluteString
                    save()
                } label: {
                    HStack(spacing: 10) {
                        TechnicalIcon(name: "arrow.uturn.backward")
                        Text("Use Built-in Endpoint")
                            .font(Theme.listRowTitle)
                            .foregroundStyle(Theme.primaryText)
                    }
                    .frame(minHeight: Theme.rowMinHeight)
                }
            } header: {
                TechnicalSectionHeader(title: "Default")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .listRowBackground(Theme.surface)
        .listRowSeparatorTint(Theme.separator)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Catalog Endpoint")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
            }
        }
        .onAppear { host = model.streamingHost }
        .preferredColorScheme(model.appearanceMode.colorScheme)
        .tint(accent)
    }

    private func save() {
        if model.saveStreamingHost(host) {
            dismiss()
        } else {
            errorMessage = "Enter an HTTPS address, for example https://tracks.monochrome.st."
        }
    }
}
#endif
