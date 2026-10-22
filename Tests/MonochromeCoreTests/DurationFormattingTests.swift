// DurationFormattingTests.swift: host tests for time formatting.
import Testing
@testable import MonochromeCore

@Test func formatsMinutesAndSeconds() {
    #expect(formatDuration(0) == "0:00")
    #expect(formatDuration(5) == "0:05")
    #expect(formatDuration(65) == "1:05")
    #expect(formatDuration(3_599) == "59:59")
}

@Test func formatsHours() {
    #expect(formatDuration(3_600) == "1:00:00")
    #expect(formatDuration(3_725) == "1:02:05")
}

@Test func formatsInvalidInputAsZero() {
    #expect(formatDuration(-10) == "0:00")
    #expect(formatDuration(.nan) == "0:00")
    #expect(formatDuration(.infinity) == "0:00")
}
