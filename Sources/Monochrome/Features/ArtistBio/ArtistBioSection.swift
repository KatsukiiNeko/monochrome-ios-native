// ArtistBioSection.swift: collapsible biography with outbound links on the artist page.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

struct ArtistBioSection: View {
    let biography: String
    var externalLink: URL?
    var socialLinks: [URL]

    @Environment(\.openURL) private var openURL
    @Environment(\.accentColor) private var accent
    @State private var isExpanded = false

    var body: some View {
        Section {
            Text(biography)
                .font(Theme.rowSubtitle)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(isExpanded ? nil : 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Artist biography")

            if biography.split(separator: " ").count > 40 {
                Button(isExpanded ? "Show Less" : "Show More") {
                    withAnimation(.default) { isExpanded.toggle() }
                }
                .font(Theme.rowSubtitle)
                .foregroundStyle(accent)
                .accessibilityLabel(isExpanded ? "Collapse biography" : "Expand biography")
            }

            if let externalLink {
                outboundRow(label: "Artist Link", url: externalLink)
            }
            ForEach(socialLinks, id: \.absoluteString) { link in
                outboundRow(label: hostName(link), url: link)
            }
        } header: {
            TechnicalSectionHeader(title: "About")
        }
    }

    private func outboundRow(label: String, url: URL) -> some View {
        Button {
            openURL(url)
        } label: {
            HStack(spacing: 8) {
                Text(label)
                    .font(Theme.rowTitle)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(Theme.caption)
                    .foregroundStyle(accent)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label), opens in Safari")
        .accessibilityHint(url.absoluteString)
    }

    /// A readable row label: the host without "www.", or the full URL when it is opaque.
    private func hostName(_ url: URL) -> String {
        guard let host = url.host() else { return url.absoluteString }
        var name = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        if let base = name.split(separator: ".").first { name = String(base) }
        return name.capitalized
    }
}
#endif
