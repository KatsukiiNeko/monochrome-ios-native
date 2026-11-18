// LayeringImportTests.swift: core must not reach into UI frameworks.
import Foundation
import Testing

@Suite("Layering imports")
struct LayeringImportTests {
    @Test("core sources import no UI framework")
    func coreHasNoUIImports() throws {
        let root = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let core = root.appending(path: "Sources/MonochromeCore")
        let files = try FileManager.default.subpathsOfDirectory(atPath: core.path)
            .filter { $0.hasSuffix(".swift") }
        let forbidden = ["SwiftUI", "UIKit", "AppKit"]
        var offenders: [String] = []
        for file in files {
            let text = try String(contentsOf: core.appending(path: file), encoding: .utf8)
            for line in text.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("import ") else { continue }
                for name in forbidden where trimmed == "import \(name)" {
                    offenders.append("\(file): \(trimmed)")
                }
            }
        }
        #expect(offenders.isEmpty, "Core must not import UI frameworks: \(offenders)")
    }
}