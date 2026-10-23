// SettingsView.swift: grouped preferences, catalog control and storage entries.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

struct SettingsView: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var isConfirmingClearCache = false
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
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.primaryText)
            }
        }
        .task {
            await refreshStorage()
            // Keep the usage row honest while playback fills or evicts cache entries.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                await refreshStorage()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshStorage() }
        }
        // The sheet has its own presentation environment; apply the authoritative
        // appearance here as well as at the root so an open sheet re-resolves now.
        .preferredColorScheme(model.appearanceMode.colorScheme)
        .tint(Theme.accent)
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
            .tint(Theme.accent)
            .accessibilityLabel("Appearance")
        } header: {
            TechnicalSectionHeader(title: "Appearance")
        }
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
            .tint(Theme.accent)

            NavigationLink {
                StreamingEndpointView(model: model)
            } label: {
                settingsLabel(icon: "link", title: "Catalog Endpoint", value: endpointValue)
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
            HStack(spacing: 10) {
                TechnicalIcon(name: "internaldrive")
                Text("Cache Usage")
                    .font(Theme.listRowTitle)
                    .foregroundStyle(Theme.primaryText)
                Spacer(minLength: 8)
                TechnicalLabel(text: byteText(model.cacheSizeBytes), color: Theme.primaryText)
            }
            .frame(minHeight: Theme.rowMinHeight)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Cache Usage, \(byteText(model.cacheSizeBytes))")

            Button(role: .destructive) {
                isConfirmingClearCache = true
            } label: {
                settingsLabel(icon: "trash", title: "Clear Cache", destructive: true)
            }
            .confirmationDialog(
                "Clear the temporary cache?",
                isPresented: $isConfirmingClearCache,
                titleVisibility: .visible
            ) {
                Button("Clear Cache", role: .destructive) {
                    Task { await model.clearCache() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Temporary playback files are removed. Downloads and imported music are not affected.")
            }
        } header: {
            TechnicalSectionHeader(title: "Cache")
        } footer: {
            Text("Temporary files used for playback. Clearing the cache never removes permanent files.")
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

    private func refreshStorage() async {
        await model.refreshCacheSize()
        await model.refreshDownloads()
    }

    private var endpointValue: String {
        guard let host = URL(string: model.streamingHost)?.host, !host.isEmpty else { return "Not set" }
        return host
    }

    private var downloadsValue: String {
        let count = model.completedDownloads.count
        guard count > 0 else { return "None" }
        let songs = count == 1 ? "1 song" : "\(count) songs"
        return "\(songs) · \(byteText(model.downloadsBytes))"
    }

    private func byteText(_ bytes: Int) -> String {
        guard bytes > 0 else { return "0 bytes" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

// MARK: - Catalog endpoint

private struct StreamingEndpointView: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @State private var host = ""
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                TextField("https://tracks.monochrome.st", text: $host)
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
        .tint(Theme.accent)
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
