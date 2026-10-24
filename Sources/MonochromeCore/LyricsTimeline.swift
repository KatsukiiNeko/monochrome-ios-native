// LyricsTimeline.swift: active-line lookup for synced lyrics.
import Foundation

public enum LyricsTimeline {
    /// A small lead makes a line appear just before its timestamp is reached.
    public static let defaultLead: TimeInterval = 0.15

    /// Returns the index of the last line at or before `position + offset + lead`.
    /// Unsorted input is rejected instead of returning a wrong line.
    public static func activeIndex(
        in lines: [LyricLine],
        position: TimeInterval,
        offset: TimeInterval = 0,
        lead: TimeInterval = defaultLead
    ) -> Int? {
        guard !lines.isEmpty else { return nil }
        guard isSorted(lines) else { return nil }

        let target = position + offset + lead
        guard target >= lines[0].time else { return nil }

        var low = 0
        var high = lines.count - 1
        var found: Int?
        while low <= high {
            let middle = low + (high - low) / 2
            if lines[middle].time <= target {
                found = middle
                low = middle + 1
            } else {
                high = middle - 1
            }
        }

        // A timed line with no text marks an instrumental gap. It must not take
        // the highlight; the last sung line stays active until the next one.
        guard var index = found else { return nil }
        while index >= 0 {
            if !lines[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return index
            }
            index -= 1
        }
        return nil
    }

    /// Positive manual values move the highlight later; the output route delays
    /// the heard sound, so its measured latency moves the highlight later too.
    public static func offset(manual: TimeInterval, outputLatency: TimeInterval) -> TimeInterval {
        -(manual + max(0, outputLatency))
    }

    public static func isSorted(_ lines: [LyricLine]) -> Bool {
        guard lines.count > 1 else { return true }
        for index in 1..<lines.count where lines[index].time < lines[index - 1].time {
            return false
        }
        return true
    }
}
