// MonochromeWidget.swift: the widget extension; reads only the shared snapshot.
#if canImport(WidgetKit)
import MonochromeCore
import SwiftUI
import WidgetKit

struct TurntableEntry: TimelineEntry {
    let date: Date
    let snapshotDate: Date?
}

struct TurntableProvider: TimelineProvider {
    func placeholder(in context: Context) -> TurntableEntry {
        TurntableEntry(date: .now, snapshotDate: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (TurntableEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TurntableEntry>) -> Void) {
        let entry = entry()
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(3600))))
    }

    private func entry() -> TurntableEntry {
        TurntableEntry(date: .now, snapshotDate: SnapshotStore.shared().read()?.date)
    }
}

struct TurntableWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Turntable", provider: TurntableProvider()) { entry in
            VStack(spacing: 4) {
                Text("Turntable")
                Text(entry.snapshotDate?.formatted(date: .omitted, time: .standard) ?? "NO GROUP")
                    .font(.caption)
            }
            .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Turntable")
        .description("A record that spins while music plays.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct MonochromeWidgetBundle: WidgetBundle {
    var body: some Widget {
        TurntableWidget()
    }
}
#endif
