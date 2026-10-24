// AboutView.swift: verified project, license and content-licensing information.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

struct AboutView: View {
    let model: AppModel

    @Environment(\.accentColor) private var accent

    private static let repositoryURL = URL(string: "https://github.com/KatsukiiNeko/monochrome-ios-native")!
    private static let upstreamURL = URL(string: "https://github.com/monochrome-music/monochrome")!
    private static let apacheURL = URL(string: "https://www.apache.org/licenses/LICENSE-2.0")!

    var body: some View {
        List {
            Section {
                LabeledContent("Project", value: "Monochrome")
                LabeledContent("Version") {
                    Text(versionText)
                        .font(Theme.value)
                        .foregroundStyle(Theme.secondaryText)
                }
                Link("Repository", destination: Self.repositoryURL)
                Text("A native SwiftUI client derived from the open-source Monochrome music player. No account, analytics or tracking SDK is included.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            } header: {
                TechnicalSectionHeader(title: "Developer")
            }

            Section {
                LabeledContent("Source Code", value: "Apache License 2.0")
                Link("Apache License 2.0", destination: Self.apacheURL)
                NavigationLink("Attribution and Notices") {
                    LicenseNoticeView(model: model)
                }
            } header: {
                TechnicalSectionHeader(title: "License")
            }

            Section {
                Text("Music, artwork and catalog data come from a third-party service. The Apache-2.0 source-code license does not grant rights to that content.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                NavigationLink("Music Licensing and Disclaimer") {
                    MusicLicensingView(model: model)
                }
            } header: {
                TechnicalSectionHeader(title: "Music Licensing")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .listRowBackground(Theme.surface)
        .listRowSeparatorTint(Theme.separator)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(model.appearanceMode.colorScheme)
        .tint(accent)
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }
}

// MARK: - Attribution

private struct LicenseNoticeView: View {
    let model: AppModel

    @Environment(\.accentColor) private var accent

    private static let apacheURL = URL(string: "https://www.apache.org/licenses/LICENSE-2.0")!
    private static let upstreamURL = URL(string: "https://github.com/monochrome-music/monochrome")!

    var body: some View {
        List {
            Section {
                Text("This product is a derivative work of the Monochrome music player, Copyright 2026 Monochrome Team, licensed under the Apache License, Version 2.0.")
                    .fixedSize(horizontal: false, vertical: true)
                Link("Monochrome on GitHub", destination: Self.upstreamURL)
            } header: {
                TechnicalSectionHeader(title: "Upstream")
            }

            Section {
                Text("The Swift/SwiftUI implementation under Sources/ and Tests/ is new work by this repository's contributors and is distributed under the same Apache License 2.0.")
                    .fixedSize(horizontal: false, vertical: true)
                Link("Apache License 2.0", destination: Self.apacheURL)
            } header: {
                TechnicalSectionHeader(title: "Repository")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .listRowBackground(Theme.surface)
        .listRowSeparatorTint(Theme.separator)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Attribution")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(model.appearanceMode.colorScheme)
        .tint(accent)
    }
}

// MARK: - Music licensing

private struct MusicLicensingView: View {
    let model: AppModel

    @Environment(\.accentColor) private var accent

    var body: some View {
        List {
            Section {
                Text("Monochrome is an independent client. Recordings, artwork and catalog data are provided by a third-party catalog service, not by this project.")
                Text("The Apache-2.0 license in this repository applies only to the source code. It does not grant any rights to recordings, artwork, metadata or catalog data.")
                Text("Availability of a track through the catalog does not by itself establish permission to download, redistribute or publicly perform it. Permanent downloads keep a local copy of the stream the catalog serves; they do not transfer rights.")
                Text("You are responsible for complying with the terms of the services you use and with applicable copyright and other laws.")
                Text("Third-party services and their catalogs can change, restrict or remove content at any time.")
            } header: {
                TechnicalSectionHeader(title: "Notice")
            } footer: {
                Text("This notice is general information, not legal advice.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .listRowBackground(Theme.surface)
        .listRowSeparatorTint(Theme.separator)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Music Licensing")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(model.appearanceMode.colorScheme)
        .tint(accent)
    }
}
#endif
