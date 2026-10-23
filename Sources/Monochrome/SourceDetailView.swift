// SourceDetailView.swift: real capabilities for each source, without fake controls.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

struct SourceDetailView: View {
    let model: AppModel
    let source: MusicSourceID

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                header
                capabilityCard
                configurationCard
            }
            .padding(Theme.screenPadding)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(source.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(model.appearanceMode.colorScheme)
    }

    private var header: some View {
        HStack(spacing: Theme.rowSpacing) {
            Image(systemName: source == .monochrome ? "waveform" : "play.rectangle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .frame(width: 52, height: 52)
                .background(
                    Theme.elevated,
                    in: RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                        .stroke(Theme.border, lineWidth: Theme.hairline)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(source.displayName)
                    .font(Theme.screenTitle)
                    .foregroundStyle(Theme.primaryText)
                Text(statusText)
                    .font(Theme.rowSubtitle)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private var capabilityCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CAPABILITIES")
                .font(Theme.micro)
                .tracking(1.0)
                .foregroundStyle(Theme.tertiaryText)
                .padding(.bottom, 10)

            capabilityRow("Search", enabled: source.capabilities.contains(.search))
            divider
            capabilityRow("Streaming", enabled: source.capabilities.contains(.stream))
            divider
            capabilityRow("Permanent downloads", enabled: source.supportsDownloads)
        }
        .padding(Theme.cardPadding)
        .background(
            Theme.surface,
            in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.border, lineWidth: Theme.hairline)
        }
    }

    private var configurationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CONFIGURATION")
                .font(Theme.micro)
                .tracking(1.0)
                .foregroundStyle(Theme.tertiaryText)

            if source == .monochrome {
                Text(model.isStreamingConfigured ? hostName : "Streaming is off")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(Theme.primaryText)
                    .textSelection(.enabled)
                Text("Change the catalog endpoint in Settings. Downloads use the same progressive FLAC stream the player uses.")
                    .font(Theme.rowSubtitle)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Companion server only")
                    .font(Theme.rowTitle)
                    .foregroundStyle(Theme.primaryText)
                Text("No server is configured in this build. The app never extracts YouTube audio, uses cookies, scrapes, or calls a direct YouTube API. A user-run HTTPS companion server is the only permitted integration.")
                    .font(Theme.rowSubtitle)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Downloads stay off for this source.")
                    .font(Theme.rowSubtitle)
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.cardPadding)
        .background(
            Theme.surface,
            in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.border, lineWidth: Theme.hairline)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: Theme.hairline)
            .accessibilityHidden(true)
    }

    private func capabilityRow(_ title: String, enabled: Bool) -> some View {
        HStack(spacing: Theme.rowSpacing) {
            Image(systemName: enabled ? "checkmark" : "xmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(enabled ? Theme.accent : Theme.tertiaryText)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(title)
                .font(Theme.rowTitle)
                .foregroundStyle(Theme.primaryText)
            Spacer(minLength: 8)
            TechnicalLabel(text: enabled ? "ON" : "OFF")
        }
        .frame(minHeight: Theme.rowMinHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(enabled ? "available" : "not available")")
    }

    private var hostName: String {
        guard let url = URL(string: model.streamingHost), let host = url.host else {
            return model.streamingHost
        }
        return host
    }

    private var statusText: String {
        switch source {
        case .monochrome:
            model.isStreamingConfigured ? "Configured" : "Streaming off"
        case .youTubeMusic:
            "Needs setup"
        }
    }
}
#endif
