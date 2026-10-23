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
        Section("Appearance") {
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
            .accessibilityLabel("Appearance")
        }
    }

    // MARK: - Streaming endpoint

    private var streamingSection: some View {
        Section {
            Toggle(
                "Enable Monochrome",
                isOn: Binding(
                    get: { model.isMonochromeEnabled },
                    set: { model.setMonochromeEnabled($0) }
                )
            )
            .tint(Theme.accent)

            NavigationLink {
                StreamingEndpointView(model: model)
            } label: {
                LabeledContent("Catalog Endpoint", value: endpointValue)
            }

            Button("Reset Endpoint", role: .destructive) {
                if model.hasCustomStreamingEndpoint {
                    isConfirmingEndpointReset = true
                } else {
                    model.resetStreamingEndpoint()
                }
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
            Text("Streaming Endpoint")
        } footer: {
            Text("Monochrome supplies the online catalog and streaming. Local files and downloads stay available when it is off.")
        }
    }

    // MARK: - Cache

    private var cacheSection: some View {
        Section {
            LabeledContent("Cache Usage", value: byteText(model.cacheSizeBytes))

            Button("Clear Cache", role: .destructive) {
                isConfirmingClearCache = true
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
            Text("Cache")
        } footer: {
            Text("Temporary files used for playback. Clearing the cache never removes permanent files.")
        }
    }

    // MARK: - Downloads

    private var downloadsSection: some View {
        Section("Downloads") {
            NavigationLink {
                DownloadsView(model: model)
            } label: {
                LabeledContent("Manage Downloads", value: downloadsValue)
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("About") {
            NavigationLink {
                AboutView(model: model)
            } label: {
                Text("About Monochrome")
            }
        }
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
                Text("Address")
            } footer: {
                Text(
                    errorMessage
                        ?? "HTTPS only. The built-in endpoint is \(StreamingSettings.defaultBaseURL.absoluteString)."
                )
                .foregroundStyle(errorMessage == nil ? Theme.secondaryText : Theme.destructive)
            }

            Section {
                Button("Use Built-in Endpoint") {
                    host = StreamingSettings.defaultBaseURL.absoluteString
                    save()
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
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
