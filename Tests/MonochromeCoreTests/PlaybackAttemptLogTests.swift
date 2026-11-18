// PlaybackAttemptLogTests.swift: the attempt state machine and its safe summary.
import Foundation
import Testing
@testable import MonochromeCore

@Suite("Playback attempt log")
struct PlaybackAttemptLogTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("the start records a tap and a short track hash")
    func initialEvent() {
        let log = PlaybackAttemptLog(trackKey: "monochrome|abc123", at: start)
        #expect(log.events.map(\.phase) == [.tap])
        #expect(log.trackKeyHash.count == 8)
        #expect(log.trackKeyHash.allSatisfy { $0.isHexDigit })
        #expect(log.trackKeyHash != PlaybackAttemptLog.hash("monochrome|other"))
        #expect(log.trackKeyHash == PlaybackAttemptLog.hash("monochrome|abc123"))
    }

    @Test("each phase reports the time since the phase before it")
    func durations() {
        var log = PlaybackAttemptLog(trackKey: "monochrome|a", at: start)
        log.mark(.lookup, at: start.addingTimeInterval(0.004), detail: "cache-miss")
        log.mark(.resolve, at: start.addingTimeInterval(0.018))
        log.mark(.asset, at: start.addingTimeInterval(0.700), detail: "network")
        log.mark(.ready, at: start.addingTimeInterval(0.842), detail: "network")

        #expect(log.durationMs(of: .lookup) == 4)
        #expect(log.durationMs(of: .resolve) == 14)
        #expect(log.durationMs(of: .asset) == 682)
        #expect(log.durationMs(of: .ready) == 142)
        #expect(log.elapsedMs(to: .ready) == 842)
        #expect(!log.isFailed)
    }

    @Test("a retried lookup measures only the last lookup")
    func repeatedPhase() {
        var log = PlaybackAttemptLog(trackKey: "monochrome|a", at: start)
        log.mark(.lookup, at: start.addingTimeInterval(0.002), detail: "download-miss")
        log.mark(.lookup, at: start.addingTimeInterval(0.005), detail: "cache-hit")
        #expect(log.durationMs(of: .lookup) == 3)
    }

    @Test("request counts are kept per consumer")
    func requestCounts() {
        var log = PlaybackAttemptLog(trackKey: "monochrome|a", at: start)
        log.countRequest("item")
        log.countRequest("item")
        log.countRequest("cache")
        #expect(log.requests == ["item": 2, "cache": 1])
        #expect(log.summary.contains("requests=cache:1,item:2"))
    }

    @Test("the summary carries times and notes but no track key")
    func summaryLine() {
        var log = PlaybackAttemptLog(trackKey: "monochrome|opaque-id-123", at: start)
        log.mark(.lookup, at: start.addingTimeInterval(0.004), detail: "cache-miss")
        log.mark(.resolve, at: start.addingTimeInterval(0.018))
        log.mark(.asset, at: start.addingTimeInterval(0.020), detail: "network")
        log.mark(.ready, at: start.addingTimeInterval(0.842), detail: "network")

        let line = log.summary
        #expect(line.hasPrefix("attempt="))
        #expect(line.contains("track=\(log.trackKeyHash)"))
        #expect(line.contains("lookup=4ms cache-miss"))
        #expect(line.contains("resolve=14ms"))
        #expect(line.contains("ready=842ms"))
        #expect(line.contains("via=network"))
        #expect(!line.contains("opaque-id-123"))
    }

    @Test("a failure records domain and code with one underlying level")
    func failure() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorResourceUnavailable,
            userInfo: [
                NSUnderlyingErrorKey: NSError(
                    domain: "AVFoundationErrorDomain",
                    code: -11800
                ),
            ]
        )
        var log = PlaybackAttemptLog(trackKey: "monochrome|a", at: start)
        log.mark(.failed, at: start.addingTimeInterval(0.5), detail: PlaybackAttemptLog.errorDetail(error))

        #expect(log.isFailed)
        #expect(log.summary.contains("failed=500ms"))
        #expect(log.summary.contains("error=NSURLErrorDomain/-1008 under=AVFoundationErrorDomain/-11800"))
        #expect(PlaybackAttemptLog.errorDetail(error).contains("https") == false)
    }
}
