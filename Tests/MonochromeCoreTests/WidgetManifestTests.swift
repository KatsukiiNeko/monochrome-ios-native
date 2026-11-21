// WidgetManifestTests.swift: the extension manifest must match the app.
import Foundation
import Testing

/// A wrong extension plist or App Group is invisible until an install fails,
/// and no device is available here, so the files are checked as text.
@Suite("Widget manifest")
struct WidgetManifestTests {
    let root = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    func text(_ path: String) throws -> String {
        try String(contentsOf: root.appending(path: path), encoding: .utf8)
    }

    func value(_ key: String, in plist: String) -> String? {
        guard let keyRange = plist.range(of: "<key>\(key)</key>") else { return nil }
        let rest = plist[keyRange.upperBound...]
        guard let open = rest.range(of: "<string>"),
              let close = rest.range(of: "</string>", range: open.upperBound..<rest.endIndex)
        else { return nil }
        return String(rest[open.upperBound..<close.lowerBound])
    }

    @Test func extensionVersionsMatchTheApp() throws {
        let app = try text("Resources/Info.plist")
        let widget = try text("Resources/MonochromeWidget-Info.plist")
        for key in ["CFBundleShortVersionString", "CFBundleVersion"] {
            #expect(value(key, in: widget) == value(key, in: app), "\(key) must match the app")
        }
    }

    @Test func theExtensionIsAWidgetKitExtension() throws {
        let widget = try text("Resources/MonochromeWidget-Info.plist")
        #expect(widget.contains("com.apple.widgetkit-extension"))
    }

    @Test func bothTargetsShareExactlyOneAppGroup() throws {
        let app = try text("Resources/Monochrome.entitlements")
        let widget = try text("Resources/MonochromeWidget.entitlements")
        let group = "group.com.katsukiineko.monochrome"
        #expect(app.contains(group))
        #expect(widget.contains(group))
        for file in [app, widget] {
            #expect(file.components(separatedBy: "<string>").count - 1 == 1, "xtool accepts one app group")
        }
    }

    @Test func xtoolDeclaresTheExtensionProduct() throws {
        let config = try text("xtool.yml")
        #expect(config.contains("product: Monochrome"))
        #expect(config.contains("product: MonochromeWidget"))
        #expect(config.contains("entitlementsPath: Resources/MonochromeWidget.entitlements"))
    }
}
