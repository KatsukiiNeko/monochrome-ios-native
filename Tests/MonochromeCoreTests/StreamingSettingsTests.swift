// StreamingSettingsTests.swift: host tests for the persisted streaming host rules.
import Foundation
import Testing
@testable import MonochromeCore

private func makeSettings() throws -> (StreamingSettings, UserDefaults, String) {
    let suite = "monochrome-settings-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    return (StreamingSettings(defaults: defaults), defaults, suite)
}

@Suite("StreamingSettings")
struct StreamingSettingsTests {
    @Test func defaultsToTheCatalogHost() throws {
        let (settings, defaults, suite) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(settings.baseURL == StreamingSettings.defaultBaseURL)
        #expect(settings.rawValue == StreamingSettings.defaultBaseURL.absoluteString)
    }

    @Test func storesACustomHost() throws {
        let (settings, defaults, suite) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        settings.setBaseURL("  https://music.example.test  ")

        #expect(settings.baseURL?.absoluteString == "https://music.example.test")
        #expect(settings.rawValue == "https://music.example.test")
    }

    @Test func emptyValueSwitchesStreamingOff() throws {
        let (settings, defaults, suite) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        settings.setBaseURL("")

        #expect(settings.baseURL == nil)
    }

    @Test func resetRestoresTheDefault() throws {
        let (settings, defaults, suite) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        settings.setBaseURL("")
        settings.reset()

        #expect(settings.baseURL == StreamingSettings.defaultBaseURL)
    }

    @Test func refusesPlainHTTPAndGarbage() {
        #expect(StreamingSettings.baseURL(from: "http://music.example.test") == nil)
        #expect(StreamingSettings.baseURL(from: "not a url") == nil)
        #expect(StreamingSettings.baseURL(from: "https://") == nil)
        #expect(StreamingSettings.baseURL(from: "https://music.example.test/base/")?.host == "music.example.test")
    }
}
