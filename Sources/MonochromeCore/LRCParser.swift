// LRCParser.swift: tolerant parsing of LRC into sorted, absolute-time lines.
import Foundation

/// Parses the synced-lyrics format. Malformed input yields fewer lines, never a crash.
public enum LRCParser {
    /// `[mm:ss]`, `[mm:ss.xx]`, `[mm:ss.xxx]` and several tags on one line.
    private static let timestampPattern = #"^\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#
    /// Enhanced LRC word timing, removed from the displayed text.
    private static let wordTagPattern = #"<\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?>"#
    private static let offsetPattern = #"\[offset:\s*([+-]?\d+)\s*\]"#

    public static func parse(_ text: String) -> [LyricLine] {
        var source = text
        if source.hasPrefix("\u{FEFF}") { source.removeFirst() }
        source = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let offset = parseOffset(source)
        let timestamp = try? NSRegularExpression(pattern: timestampPattern)
        let wordTag = try? NSRegularExpression(pattern: wordTagPattern)
        var lines: [LyricLine] = []

        for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
            var remainder = String(rawLine)
            var times: [TimeInterval] = []

            while remainder.hasPrefix("["), let timestamp {
                let range = NSRange(remainder.startIndex..., in: remainder)
                guard let match = timestamp.firstMatch(in: remainder, range: range),
                      match.range.location == 0,
                      let fullRange = Range(match.range, in: remainder),
                      let minutes = integer(match, group: 1, in: remainder),
                      let seconds = integer(match, group: 2, in: remainder),
                      seconds < 60
                else { break }

                let fraction = fractionSeconds(match, group: 3, in: remainder)
                times.append(TimeInterval(minutes * 60 + seconds) + fraction)
                remainder = String(remainder[fullRange.upperBound...])
            }

            guard !times.isEmpty else { continue }

            if let wordTag {
                remainder = wordTag.stringByReplacingMatches(
                    in: remainder,
                    range: NSRange(remainder.startIndex..., in: remainder),
                    withTemplate: ""
                )
            }
            let lyric = remainder.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            for time in times {
                lines.append(LyricLine(time: max(0, time + offset), text: lyric))
            }
        }

        // Stable sort: equal timestamps keep their original order.
        return lines.enumerated().sorted {
            if $0.element.time == $1.element.time { return $0.offset < $1.offset }
            return $0.element.time < $1.element.time
        }.map(\.element)
    }

    private static func parseOffset(_ text: String) -> TimeInterval {
        guard let regex = try? NSRegularExpression(pattern: offsetPattern, options: [.caseInsensitive]) else {
            return 0
        }
        var offset: TimeInterval = 0
        let range = NSRange(text.startIndex..., in: text)
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match, let value = integer(match, group: 1, in: text) else { return }
            offset = TimeInterval(value) / 1000
        }
        return offset
    }

    private static func integer(
        _ match: NSTextCheckingResult,
        group: Int,
        in text: String
    ) -> Int? {
        guard group < match.numberOfRanges else { return nil }
        let range = match.range(at: group)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else {
            return nil
        }
        return Int(text[swiftRange])
    }

    /// `.5` and `.50` mean 500 ms; `.500` means the same. Missing fraction is zero.
    private static func fractionSeconds(
        _ match: NSTextCheckingResult,
        group: Int,
        in text: String
    ) -> TimeInterval {
        guard group < match.numberOfRanges else { return 0 }
        let range = match.range(at: group)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else {
            return 0
        }
        let digits = text[swiftRange]
        guard let value = Int(digits) else { return 0 }
        switch digits.count {
        case 1: return TimeInterval(value) / 10
        case 2: return TimeInterval(value) / 100
        default: return TimeInterval(value) / 1000
        }
    }
}
