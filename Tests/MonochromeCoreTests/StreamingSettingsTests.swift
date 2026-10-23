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

        settings.setBaseURL("https://music.example.test")
        settings.setEnabled(true)
        settings.reset()

        #expect(settings.baseURL == StreamingSettings.defaultBaseURL)
    }

    @Test func resetDoesNotReenableALegacyOffState() throws {
        let (settings, defaults, suite) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        settings.setBaseURL("")
        settings.reset()

        #expect(settings.configuredBaseURL == StreamingSettings.defaultBaseURL)
        #expect(settings.isEnabled == false)
        #expect(settings.baseURL == nil)
    }

    @Test func disabledStreamingExposesNoBaseURL() throws {
        let (settings, defaults, suite) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        settings.setEnabled(false)

        #expect(settings.isEnabled == false)
        #expect(settings.baseURL == nil)
        #expect(settings.configuredBaseURL == StreamingSettings.defaultBaseURL)
    }

    @Test func enabledStatePersistsAcrossInstances() throws {
        let (settings, defaults, suite) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        settings.setEnabled(false)
        #expect(StreamingSettings(defaults: defaults).isEnabled == false)

        settings.setEnabled(true)
        let reopened = StreamingSettings(defaults: defaults)
        #expect(reopened.isEnabled)
        #expect(reopened.baseURL == StreamingSettings.defaultBaseURL)
    }

    @Test func resetKeepsStreamingDisabled() throws {
        let (settings, defaults, suite) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        settings.setBaseURL("https://music.example.test")
        settings.setEnabled(false)
        settings.reset()

        #expect(settings.configuredBaseURL == StreamingSettings.defaultBaseURL)
        #expect(settings.isEnabled == false)
        #expect(settings.baseURL == nil)
    }

    @Test func resetLeavesUnrelatedPreferencesAlone() throws {
        let (settings, defaults, suite) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("dark", forKey: AppearanceSettings.storageKey)
        defaults.set(true, forKey: AudioCacheSettings.storageKey)
        settings.setBaseURL("https://music.example.test")
        settings.setEnabled(false)

        settings.reset()

        #expect(defaults.string(forKey: AppearanceSettings.storageKey) == "dark")
        #expect(defaults.bool(forKey: AudioCacheSettings.storageKey))
        #expect(defaults.string(forKey: StreamingSettings.storageKey) == nil)
    }

    @Test func legacyEmptyHostStaysOffWithoutAnExplicitToggle() throws {
        let (settings, defaults, suite) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        settings.setBaseURL("")

        #expect(settings.isEnabled == false)
        #expect(settings.baseURL == nil)
    }

    @Test func enablingWithoutAHostRecoversTheDefault() throws {
        let (settings, defaults, suite) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        settings.setBaseURL("")
        settings.setEnabled(true)

        #expect(settings.isEnabled)
        #expect(settings.baseURL == StreamingSettings.defaultBaseURL)
    }

    @Test func editingTheHostDoesNotReenableStreaming() throws {
        let (settings, defaults, suite) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        settings.setEnabled(false)
        settings.setBaseURL("https://music.example.test")

        #expect(settings.isEnabled == false)
        #expect(settings.baseURL == nil)
    }

    @Test func customEndpointIsOnlyReportedForAnOverride() throws {
        let (settings, defaults, suite) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(settings.hasCustomEndpoint == false)

        settings.setBaseURL(StreamingSettings.defaultBaseURL.absoluteString)
        #expect(settings.hasCustomEndpoint == false)

        settings.setBaseURL("https://music.example.test")
        #expect(settings.hasCustomEndpoint)

        settings.reset()
        #expect(settings.hasCustomEndpoint == false)
    }

    @Test func refusesPlainHTTPAndGarbage() {
        #expect(StreamingSettings.baseURL(from: "http://music.example.test") == nil)
        #expect(StreamingSettings.baseURL(from: "not a url") == nil)
        #expect(StreamingSettings.baseURL(from: "https://") == nil)
        #expect(StreamingSettings.baseURL(from: "https://music.example.test/base/")?.host == "music.example.test")
    }
}
