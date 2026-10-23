// SettingsView.swift: edit the streaming host and show whether streaming is on.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

struct SettingsView: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @State private var host = ""
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                TextField("https://tracks.monochrome.st", text: $host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .accessibilityLabel("Streaming host")
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Streaming host")
            } footer: {
                Text("Defaults to the host the Monochrome web app uses. Leave it empty to switch online streaming off; imported files keep playing. Only HTTPS is accepted.")
            }

            Section {
                Button("Use the default host") {
                    host = StreamingSettings.defaultBaseURL.absoluteString
                    save()
                }
                Button("Turn streaming off", role: .destructive) {
                    host = ""
                    save()
                }
            }

            Section {
                LabeledContent("Online streaming", value: model.isStreamingConfigured ? "On" : "Off")
            }

            Section {
                LabeledContent("Cached audio", value: "\(model.cacheEntryCount) songs, " + ByteCountFormatter.string(
                    fromByteCount: Int64(model.cacheSizeBytes),
                    countStyle: .file
                ))
                Button("Clear cache", role: .destructive) {
                    Task { await model.clearCache() }
                }
                .disabled(model.cacheEntryCount == 0)
                Toggle("Cache over cellular", isOn: Binding(
                    get: { model.allowsCellularCaching },
                    set: { model.setAllowsCellularCaching($0) }
                ))
            } header: {
                Text("Audio cache")
            } footer: {
                Text("Streams are kept on this device so replaying a track does not download it again. Up to 500 MB; the system may clear the cache at any time.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
            }
        }
        .onAppear { host = model.streamingHost }
        .task { await model.refreshCacheSize() }
    }

    private func save() {
        if model.saveStreamingHost(host) {
            errorMessage = nil
            dismiss()
        } else {
            errorMessage = "Enter an HTTPS address, for example https://tracks.monochrome.st."
        }
    }
}
#endif
