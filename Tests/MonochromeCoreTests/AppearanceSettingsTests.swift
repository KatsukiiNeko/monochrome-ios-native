// AppearanceSettingsTests.swift: persistence and fallback rules for the appearance preference.
import Foundation
import Testing
@testable import MonochromeCore

private func makeSettings() throws -> (AppearanceSettings, UserDefaults, String) {
    let suite = "monochrome-appearance-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    return (AppearanceSettings(defaults: defaults), defaults, suite)
}

@Suite("AppearanceSettings")
struct AppearanceSettingsTests {
    @Test func defaultsToSystem() throws {
        let (settings, defaults, suite) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(settings.mode == .system)
    }

    @Test func persistsEachMode() throws {
        let (settings, defaults, suite) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        for mode in AppearanceMode.allCases {
            settings.setMode(mode)
            #expect(settings.mode == mode)
            #expect(AppearanceSettings(defaults: defaults).mode == mode)
        }
    }

    @Test func unknownValueFallsBackToSystem() throws {
        let (settings, defaults, suite) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("sepia", forKey: AppearanceSettings.storageKey)

        #expect(settings.mode == .system)
    }

    @Test func resetRestoresSystem() throws {
        let (settings, defaults, suite) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        settings.setMode(.dark)
        settings.reset()

        #expect(settings.mode == .system)
    }
}
