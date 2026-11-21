// MonochromeWidget.swift: the widget entry point, configuration and timeline.
#if canImport(WidgetKit)
@_cdecl("_monochromeWidgetKeepText")
func monochromeWidgetKeepText() {}

import AppIntents
import MonochromeCore
import SwiftUI
import UIKit
import WidgetKit

#if canImport(os)
import os

private let widgetLog = Logger(subsystem: "com.katsukiineko.monochrome", category: "widget")
#endif

enum MotionOption: String, AppEnum {
    case spin
    case still

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Motion"
    static let caseDisplayRepresentations: [MotionOption: DisplayRepresentation] = [
        .spin: "Spin (experimental)",
        .still: "Still",
    ]

    var mode: MotionMode { self == .spin ? .spin : .still }
}

struct TurntableConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Turntable"

    @Parameter(title: "Motion", default: .spin)
    var motion: MotionOption
}

struct TurntableEntry: TimelineEntry {
    let date: Date
    let frame: TurntableFrame
    let title: String
    let artist: String
    let artwork: Image?
    let hasTrack: Bool
    let groupAvailable: Bool
    let animate: Bool
    let isPlaying: Bool

    var accessibilityLabel: String {
        guard groupAvailable else { return "Monochrome widget. Open Monochrome to connect." }
        guard hasTrack else { return "Not playing" }
        return "Now playing, \(title) by \(artist), \(isPlaying ? "playing" : "paused")"
    }

    static func sample(now: Date = .now) -> TurntableEntry {
        let snapshot = PlaybackSnapshot(
            trackID: "sample",
            title: "Monochrome",
            artist: "Turntable",
            duration: 200,
            position: 30,
            isPlaying: true,
            platterDegrees: 210,
            date: now
        )
        let frame = TurntablePlanner().frames(for: snapshot, now: now, mode: .spin).first
            ?? TurntableFrame(date: now, platterDegrees: 0, armRotation: 0, lift: 1)
        return TurntableEntry(
            date: now, frame: frame, title: snapshot.title, artist: snapshot.artist,
            artwork: nil, hasTrack: true, groupAvailable: true, animate: true, isPlaying: true
        )
    }
}

struct TurntableProvider: AppIntentTimelineProvider {
    var store = SnapshotStore.shared()

    func placeholder(in context: Context) -> TurntableEntry {
        .sample()
    }

    func snapshot(for configuration: TurntableConfiguration, in context: Context) async -> TurntableEntry {
        (await entries(for: configuration, now: .now)).first ?? .sample()
    }

    func timeline(for configuration: TurntableConfiguration, in context: Context) async -> Timeline<TurntableEntry> {
        let now = Date()
        let entries = await entries(for: configuration, now: now)
        let last = entries.last?.date ?? now
        #if canImport(os)
        widgetLog.info(
            "[Widget] timeline mode=\(configuration.motion.rawValue, privacy: .public) frames=\(entries.count, privacy: .public) os=\(ProcessInfo.processInfo.operatingSystemVersionString, privacy: .public)"
        )
        #endif
        // Spin steps as fast as WidgetKit allows; a still or paused deck only
        // needs an occasional refresh.
        let spinning = entries.count > 1
        return Timeline(entries: entries, policy: .after(last.addingTimeInterval(spinning ? 60 : 900)))
    }

    private func entries(for configuration: TurntableConfiguration, now: Date) async -> [TurntableEntry] {
        let snapshot = store.read() ?? .nothingPlaying
        // Reduce Motion turns Spin into the still pose; stepped jumps are still
        // motion to the person looking at the Home Screen.
        let reduceMotion = await MainActor.run { UIAccessibility.isReduceMotionEnabled }
        let motion: MotionMode = reduceMotion ? .still : configuration.motion.mode
        let frames = TurntablePlanner().frames(for: snapshot, now: now, mode: motion)
        let artwork = loadArtwork(snapshot)
        return frames.map { frame in
            TurntableEntry(
                date: frame.date,
                frame: frame,
                title: snapshot.title,
                artist: snapshot.artist,
                artwork: artwork,
                hasTrack: snapshot.trackID != nil,
                groupAvailable: store.isAvailable,
                animate: motion == .spin && snapshot.isPlaying,
                isPlaying: snapshot.isPlaying
            )
        }
    }

    private func loadArtwork(_ snapshot: PlaybackSnapshot) -> Image? {
        guard let url = store.artworkURL(named: snapshot.artworkFile),
              let image = UIImage(contentsOfFile: url.path)
        else { return nil }
        return Image(uiImage: image)
    }
}

struct TurntableWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: SnapshotStore.widgetKind,
            intent: TurntableConfiguration.self,
            provider: TurntableProvider()
        ) { entry in
            TurntableView(entry: entry)
                .containerBackground(for: .widget) { WidgetTheme.background }
        }
        .configurationDisplayName("Turntable")
        .description("A record that spins while music plays.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

@main
struct MonochromeWidgetBundle: WidgetBundle {
    init() {
        monochromeWidgetKeepText()
    }

    var body: some Widget {
        TurntableWidget()
    }
}
#endif
