// SettingsView.swift: grouped preferences, catalog control and storage entries.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

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
