// CoreLayeringTests.swift: MonochromeCore must stay portable off Apple platforms.
import Foundation
import Testing

@Suite("Core layering")
struct CoreLayeringTests {
    /// Observation is allowed because PlayerController is observable in core.
    private static let allowedImports: Set<String> = ["Foundation", "FoundationNetworking", "Observation"]

    @Test func coreImportsOnlyPortableModules() throws {
        let root = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let core = root.appending(path: "Sources/MonochromeCore")
        let files = try FileManager.default.subpathsOfDirectory(atPath: core.path)
            .filter { $0.hasSuffix(".swift") }
        try #require(files.count > 10, "The core sources should be found next to the tests.")

        var offenders: [String] = []
        for file in files {
            let text = try String(contentsOf: core.appending(path: file), encoding: .utf8)
            for line in text.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("import ") else { continue }
                let module = trimmed.dropFirst("import ".count).split(separator: " ").first.map(String.init) ?? ""
                if !Self.allowedImports.contains(module) {
                    offenders.append("\(file): \(trimmed)")
                }
            }
        }

        #expect(offenders.isEmpty, "Core must not import Apple-only frameworks: \(offenders)")
    }
}
