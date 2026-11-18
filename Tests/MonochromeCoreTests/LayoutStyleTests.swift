// LayoutStyleTests.swift: layout constants, the tab inset guard and the
// style-conformance ratchet over the feature views.
import Foundation
import Testing
@testable import MonochromeCore

@Suite("Layout spec")
struct LayoutSpecTests {
    @Test("every control target is at least 44 pt")
    func touchTargets() {
        #expect(LayoutSpec.scrubberHitTarget >= 44)
        #expect(LayoutSpec.miniPlayerHeight >= 56)
    }

    @Test("a short or narrow screen gets the compact player")
    func playerVariants() {
        // iPhone SE is short, 320 pt wide is narrow, a 812 pt phone keeps the
        // regular composition, and a tablet certainly does.
        #expect(PlayerLayout.variant(forWidth: 375, height: 667) == .compact)
        #expect(PlayerLayout.variant(forWidth: 320, height: 900) == .compact)
        #expect(PlayerLayout.variant(forWidth: 375, height: 812) == .regular)
        #expect(PlayerLayout.variant(forWidth: 393, height: 852) == .regular)
        #expect(PlayerLayout.variant(forWidth: 1024, height: 1366) == .regular)
    }

    @Test("artwork never exceeds the screen width")
    func artworkWidths() {
        #expect(PlayerLayout.artworkMaxWidth(for: .regular) == 360)
        #expect(PlayerLayout.artworkMaxWidth(for: .compact) == 264)
        #expect(PlayerLayout.artworkMaxWidth(forWidth: 320, height: 568) < 320)
    }

    @Test("the skeleton waits before showing and stays once shown")
    func skeletonTiming() {
        #expect(LayoutSpec.searchSkeletonGraceMs == 150)
        #expect(LayoutSpec.searchSkeletonMinVisibleMs >= 300)
        #expect(LayoutSpec.searchSkeletonGraceMs < LayoutSpec.searchSkeletonMinVisibleMs)
    }
}

/// Source scans. They read the repository that sits beside the test target.
private func repositoryFile(_ path: String) throws -> String {
    let root = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return try String(contentsOf: root.appending(path: path), encoding: .utf8)
}

@Suite("Layout guards")
struct LayoutGuardTests {
    @Test("every tab reserves the mini-player band")
    func tabsReserveTheMiniPlayer() throws {
        let shell = try repositoryFile("Sources/Monochrome/ContentView.swift")
        let tabs = shell.components(separatedBy: ".tabItem").count - 1
        let insets = shell.components(separatedBy: ".nowPlayingBarInset").count - 1
        #expect(tabs == 3, "The app has three tabs; update this guard with the spec.")
        #expect(insets >= tabs, "Each tab root needs the bottom inset so the last row stays visible.")
    }

    @Test("no other file starts a TabView")
    func oneTabView() throws {
        let root = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appending(path: "Sources/Monochrome")
        let files = try FileManager.default.subpathsOfDirectory(atPath: sources.path)
            .filter { $0.hasSuffix(".swift") }
        var offenders: [String] = []
        for file in files where file != "ContentView.swift" {
            let text = try String(contentsOf: sources.appending(path: file), encoding: .utf8)
            if text.contains("TabView(") { offenders.append(file) }
        }
        #expect(offenders.isEmpty, "The shell is the only place a TabView belongs: \(offenders)")
    }

    /// Lines that may still hold a literal color or a raw font size. A new one
    /// fails the test; removing an old one is always allowed.
    private static let allowedOffenders: Set<String> = [
        "TechnicalIcon.swift: .font(.system(size: 13, weight: .semibold))",
        "SearchView.swift: .font(.system(size: 34))",
        "RoundPlayButton.swift: .font(.system(size: size * 0.38, weight: .bold))",
    ]

    @Test("feature views take colors and fonts from Theme")
    func styleConformance() throws {
        let root = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appending(path: "Sources/Monochrome")
        let files = try FileManager.default.subpathsOfDirectory(atPath: sources.path)
            .filter { $0.hasSuffix(".swift") && $0 != "Theme.swift" }

        let literalColor = try Regex(#"Color\((red:|white:)|UIColor\(|#[0-9a-fA-F]{6}\b"#)
        let rawFont = try Regex(#"\.font\(\.system\(size:"#)
        var offenders: Set<String> = []
        for file in files {
            let text = try String(contentsOf: sources.appending(path: file), encoding: .utf8)
            for line in text.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") { continue }
                if trimmed.contains(literalColor) || trimmed.contains(rawFont) {
                    offenders.insert("\(file): \(trimmed)")
                }
            }
        }
        let added = offenders.subtracting(Self.allowedOffenders)
        #expect(added.isEmpty, "Views must use Theme tokens for colors and fonts: \(added.sorted())")
    }
}
