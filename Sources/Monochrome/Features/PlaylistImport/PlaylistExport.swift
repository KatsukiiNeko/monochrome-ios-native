// PlaylistExport.swift: writes a playlist to a shareable file.
#if canImport(SwiftUI)
import Foundation
import MonochromeCore

enum PlaylistExport {
    /// Share files live in a temporary folder; the system sheet copies them.
    static func writeJSON(name: String, items: [Track]) throws -> URL {
        let data = try PlaylistFileParser.appExportJSON(name: name, items: items)
        let url = try destination(name: name, extension: "json")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func writeCSV(name: String, items: [Track]) throws -> URL {
        let csv = PlaylistFileParser.appExportCSV(items: items)
        let url = try destination(name: name, extension: "csv")
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func destination(name: String, extension fileExtension: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PlaylistExports", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safeName = name
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return folder.appendingPathComponent(
            (safeName.isEmpty ? "Playlist" : safeName) + "." + fileExtension
        )
    }
}
#endif
