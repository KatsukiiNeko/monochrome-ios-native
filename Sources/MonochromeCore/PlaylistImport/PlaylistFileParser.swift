// PlaylistFileParsers.swift: read CSV, M3U, plain-text and the app's own JSON
// playlist files into entries the importer can match against the catalog.
import Foundation

public struct PlaylistImportEntry: Codable, Equatable, Sendable {
    public var title: String
    public var artist: String
    public var album: String?
    public var durationSeconds: Double?
    /// Present only when the file is the app's own export carrying full snapshots.
    public var snapshot: Track?

    public init(
        title: String,
        artist: String,
        album: String? = nil,
        durationSeconds: Double? = nil,
        snapshot: Track? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.durationSeconds = durationSeconds
        self.snapshot = snapshot
    }
}

public struct PlaylistParseResult: Equatable, Sendable {
    public enum Format: String, Sendable {
        case csv = "CSV"
        case m3u = "M3U"
        case text = "Text"
        case json = "JSON"
    }

    public var format: Format
    public var entries: [PlaylistImportEntry]
    /// Lines that could not be turned into an entry, reported so the UI is honest.
    public var skipped: Int
    /// Playlist name from the file, when the format carries one.
    public var playlistName: String?

    public init(format: Format, entries: [PlaylistImportEntry], skipped: Int = 0, playlistName: String? = nil) {
        self.format = format
        self.entries = entries
        self.skipped = skipped
        self.playlistName = playlistName
    }
}

public enum PlaylistFileParser {
    /// Detects the format and parses. Empty input yields no entries.
    public static func parse(_ data: Data) -> PlaylistParseResult {
        let text = decodeText(data)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return PlaylistParseResult(format: .text, entries: [], skipped: 0)
        }
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            if let result = parseAppJSON(text) { return result }
        }
        if trimmed.contains("#EXTM3U") || trimmed.contains("#EXTINF") {
            return parseM3U(text)
        }
        // "Artist - Title" lines without any field separator are plain text.
        let lines = trimmed.split(whereSeparator: \.isNewline).map(String.init)
        let hasSeparator = lines.contains { $0.contains(",") || $0.contains(";") || $0.contains("\t") }
        let looksLikeText = lines.contains { !splitArtistTitle($0).artist.isEmpty }
        if !hasSeparator && looksLikeText {
            return parseText(text)
        }
        return parseCSV(text)
    }

    static func decodeText(_ data: Data) -> String {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        // A UTF-16 BOM can slip in from Windows editors.
        if let utf16 = String(data: data, encoding: .utf16) { return utf16 }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - CSV

    /// Header detection with delimiter sniffing; recognized columns are title,
    /// artist, album and duration. Without a header, columns are assumed
    /// Title, Artist.
    public static func parseCSV(_ text: String) -> PlaylistParseResult {
        let delimiter = sniffDelimiter(in: String(text.prefix(2000)))
        let rows = splitCSVRows(text.replacingOccurrences(of: "\r\n", with: "\n"), delimiter: delimiter)
            .filter { !$0.isEmpty }
        guard !rows.isEmpty else {
            return PlaylistParseResult(format: .csv, entries: [], skipped: 0)
        }

        var skipped = 0
        var entries: [PlaylistImportEntry] = []

        var columns: [String: Int]?
        var dataRows = rows
        let headerFields = rows[0].map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        let recognized = ["title", "name", "song", "track", "artist", "album", "duration", "time", "length"]
        if headerFields.contains(where: { recognized.contains($0) }) {
            columns = [:]
            for (index, field) in headerFields.enumerated() {
                switch field {
                case "title", "name", "song", "track": columns!["title", default: index] = index
                case "artist": columns!["artist", default: index] = index
                case "album": columns!["album", default: index] = index
                case "duration", "time", "length": columns!["duration", default: index] = index
                default: break
                }
            }
            dataRows = Array(rows.dropFirst())
        }

        for row in dataRows {
            guard let entry = csvEntry(row: row, columns: columns, delimiter: delimiter) else {
                // A row of empty fields is a blank line in disguise.
                skipped += 1
                continue
            }
            entries.append(entry)
        }
        return PlaylistParseResult(format: .csv, entries: entries, skipped: skipped)
    }

    private static func csvEntry(row: [String], columns: [String: Int]?, delimiter: String) -> PlaylistImportEntry? {
        func field(_ key: String) -> String? {
            if let index = columns?[key], row.indices.contains(index) {
                return row[index].trimmingCharacters(in: .whitespaces)
            }
            return nil
        }
        var title = field("title")
        var artist = field("artist")
        var album = field("album").flatMap { $0.isEmpty ? nil : $0 }
        var duration = field("duration").flatMap(parseDuration)

        if columns == nil {
            // "Artist - Title" inside one cell, or Title,Artist columns.
            let first = row.first ?? ""
            let parts = splitArtistTitle(first)
            if row.count >= 2 {
                title = row[1].trimmingCharacters(in: .whitespaces)
                artist = parts.artist.isEmpty ? row[0].trimmingCharacters(in: .whitespaces) : parts.artist
            } else if parts.artist.isEmpty {
                // A lone field without an "Artist - Title" shape has no match key.
                return nil
            } else {
                title = parts.title
                artist = parts.artist
            }
        }
        guard let title, !title.isEmpty else { return nil }
        return PlaylistImportEntry(title: title, artist: artist ?? "", album: album, durationSeconds: duration)
    }

    /// RFC 4180 quoting: `"` escapes `"` and a quoted field may contain the
    /// delimiter and newlines.
    static func splitCSVRows(_ text: String, delimiter: String = ",") -> [[String]] {
        let separator = delimiter.first ?? ","
        var rows: [[String]] = [[]]
        var field = ""
        var inQuotes = false
        var characters = Array(text)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if inQuotes {
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 2
                        continue
                    }
                    inQuotes = false
                } else {
                    field.append(character)
                }
            } else if character == "\"" {
                inQuotes = true
            } else if character == separator {
                rows[rows.count - 1].append(field)
                field = ""
            } else if character == "\n" {
                rows[rows.count - 1].append(field)
                field = ""
                rows.append([])
            } else {
                field.append(character)
            }
            index += 1
        }
        rows[rows.count - 1].append(field)
        return rows
    }

    static func sniffDelimiter(in sample: String) -> String {
        let counts: [String: Int] = [
            ",": sample.filter { $0 == "," }.count,
            ";": sample.filter { $0 == ";" }.count,
            "\t": sample.filter { $0 == "\t" }.count,
        ]
        return counts.max { $0.value < $1.value }?.key ?? ","
    }

    // MARK: - M3U / M3U8

    /// `#EXTINF` carries the duration and the label; the following path line is
    /// ignored because it holds no title.
    public static func parseM3U(_ text: String) -> PlaylistParseResult {
        var entries: [PlaylistImportEntry] = []
        var skipped = 0
        var expectPath = false
        for rawLine in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("#EXTINF:") {
                let afterColon = line.dropFirst("#EXTINF:".count)
                let durationPart = afterColon.prefix(while: { $0.isNumber || $0 == "." || $0 == "-" })
                let duration = Double(durationPart)
                guard let comma = line.range(of: ",") else { continue }
                let label = String(line[comma.upperBound...])
                let parts = splitArtistTitle(label)
                expectPath = true
                if parts.title.isEmpty {
                    skipped += 1
                    expectPath = false
                    continue
                }
                entries.append(PlaylistImportEntry(
                    title: parts.title,
                    artist: parts.artist,
                    durationSeconds: duration
                ))            } else if line.hasPrefix("#") {
                continue
            } else if expectPath {
                // The media path of the entry above.
                expectPath = false
            } else {
                skipped += 1
            }
        }
        return PlaylistParseResult(format: .m3u, entries: entries, skipped: skipped)
    }

    // MARK: - Plain text

    /// One entry per line, "Artist - Title". A line without that shape has no
    /// reliable match key and is reported as skipped.
    public static func parseText(_ text: String) -> PlaylistParseResult {
        var entries: [PlaylistImportEntry] = []
        var skipped = 0
        for rawLine in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = splitArtistTitle(line)
            if parts.artist.isEmpty {
                skipped += 1
            } else {
                entries.append(PlaylistImportEntry(title: parts.title, artist: parts.artist))
            }
        }
        return PlaylistParseResult(format: .text, entries: entries, skipped: skipped)
    }

    /// Splits on the first " - ", " – " or " — " separator.
    static func splitArtistTitle(_ line: String) -> (artist: String, title: String) {
        for separator in [" - ", " – ", " — "] {
            if let range = line.range(of: separator) {
                let artist = String(line[line.startIndex..<range.lowerBound])
                    .trimmingCharacters(in: .whitespaces)
                let title = String(line[range.upperBound...])
                    .trimmingCharacters(in: .whitespaces)
                if !artist.isEmpty, !title.isEmpty {
                    return (artist, title)
                }
            }
        }
        return ("", line.trimmingCharacters(in: .whitespaces))
    }

    // MARK: - The app's own JSON

    struct AppExport: Codable {
        var schemaVersion: Int
        var name: String?
        var items: [Track]
    }

    public static let exportSchemaVersion = 1

    /// The app's export carries full track snapshots, so a round trip needs no
    /// network matching.
    public static func parseAppJSON(_ text: String) -> PlaylistParseResult? {
        guard let data = text.data(using: .utf8) else { return nil }
        guard let export = try? JSONDecoder().decode(AppExport.self, from: data),
              export.schemaVersion >= 1 else { return nil }
        let entries = export.items.map { track in
            PlaylistImportEntry(
                title: track.title,
                artist: track.artist,
                album: track.album.isEmpty ? nil : track.album,
                durationSeconds: track.durationSeconds,
                snapshot: track
            )
        }
        return PlaylistParseResult(format: .json, entries: entries, skipped: 0, playlistName: export.name)
    }

    public static func appExportJSON(name: String?, items: [Track]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(AppExport(schemaVersion: exportSchemaVersion, name: name, items: items))
    }

    /// CSV export with a header row; fields with commas or quotes are quoted.
    public static func appExportCSV(items: [Track]) -> String {
        var lines = ["Title,Artist,Album,Duration"]
        for track in items {
            let duration = track.durationSeconds.map { formatDuration($0) } ?? ""
            lines.append([
                csvField(track.title),
                csvField(track.displayArtist),
                csvField(track.displayAlbum),
                csvField(duration),
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func csvField(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - Values

    /// "3:45" or "225" → seconds. Negative or nonsense is nil.
    public static func parseDuration(_ raw: String) -> Double? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        if let seconds = Double(text), seconds >= 0 { return seconds }
        let parts = text.split(separator: ":")
        if parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]) {
            let total = minutes * 60 + seconds
            return total >= 0 ? total : nil
        }
        return nil
    }
}
