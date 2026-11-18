// SourceServicesTests.swift: provider search, selection and resolution.
import Foundation
import Testing
@testable import MonochromeCore

private func track(_ title: String, artist: String = "A", quality: AudioQuality? = nil, provider: String = "p") -> Track {
    Track(title: title, artist: artist, provider: provider, audioQuality: quality)
}

private struct FakeProvider: MusicSourceProvider {
    let id: String
    let displayName: String = "Fake"
    let capabilities: ProviderCapabilities = [.search, .audio]
    let tracks: [Track]
    let shouldFail: Bool
    let delay: Duration

    init(id: String, tracks: [Track] = [], shouldFail: Bool = false, delay: Duration = .zero) {
        self.id = id
        self.tracks = tracks
        self.shouldFail = shouldFail
        self.delay = delay
    }

    func search(_ query: String, limit: Int) async throws -> [Track] {
        if delay > .zero { try? await Task.sleep(for: delay) }
        if shouldFail { throw ProviderError.unavailable }
        return tracks
    }

    func resolve(_ track: Track) async throws -> PlaybackSource {
        .remoteStream(url: URL(string: "https://example/\(track.id)")!, headers: [:], providerID: id, quality: track.audioQuality, contentType: nil)
    }
}

@Suite("Source search service")
struct SourceSearchServiceTests {
    @Test("one failure does not block the others")
    func partialFailure() async {
        let good = FakeProvider(id: "good", tracks: [track("Song", provider: "good")])
        let bad = FakeProvider(id: "bad", shouldFail: true)
        let service = SourceSearchService(perProviderBudget: .seconds(2))
        let results = await service.search(query: "q", limit: 10, providers: [good, bad])
        #expect(results.count == 2)
        #expect(results.first { $0.providerID == "good" }?.status == .complete)
        #expect(results.first { $0.providerID == "bad" }?.status == .failed)
    }

    @Test("empty is final only when all complete")
    func emptyFinal() async {
        let a = FakeProvider(id: "a")
        let b = FakeProvider(id: "b")
        let service = SourceSearchService()
        let results = await service.search(query: "q", limit: 10, providers: [a, b])
        #expect(results.allSatisfy { $0.tracks.isEmpty })
    }
}

@Suite("Source selection service")
struct SourceSelectionServiceTests {
    @Test("wrong recording cannot win on quality")
    func rejectsWrongRecording() {
        let requested = track("Neon", artist: "Artist", quality: .high)
        let candidates = [
            SourceCandidate(providerID: "A", track: track("Neon", artist: "Artist", quality: .lossless), quality: .lossless),
            SourceCandidate(providerID: "B", track: track("Neon", artist: "Other", quality: .hiResLossless), quality: .hiResLossless),
            SourceCandidate(providerID: "C", track: track("Neon Live", artist: "Artist", quality: .lossless), quality: .lossless),
        ]
        let ranked = SourceSelectionService().select(requested: requested, candidates: candidates, providerPriority: ["A", "B", "C"])
        #expect(ranked.count == 1)
        #expect(ranked.first?.providerID == "A")
    }

    @Test("exact FLAC preferred over exact AAC")
    func qualityThenPriority() {
        let requested = track("Neon", artist: "Artist")
        let candidates = [
            SourceCandidate(providerID: "B", track: track("Neon", artist: "Artist", quality: .high), quality: .high),
            SourceCandidate(providerID: "A", track: track("Neon", artist: "Artist", quality: .lossless), quality: .lossless),
        ]
        let ranked = SourceSelectionService().select(requested: requested, candidates: candidates, providerPriority: ["A", "B"])
        #expect(ranked.first?.providerID == "A")
    }
}

@Suite("Source resolution service")
struct SourceResolutionServiceTests {
    @Test("falls back after a failure")
    func fallback() async {
        let candidates = [
            SourceCandidate(providerID: "A", track: track("t", provider: "A")),
            SourceCandidate(providerID: "B", track: track("t", provider: "B")),
        ]
        let service = SourceResolutionService(perPlayBudget: 3)
        let result = await service.resolve(candidates: candidates) { candidate in
            if candidate.providerID == "A" { throw ProviderError.unavailable }
            return PlaybackSource.remoteStream(url: URL(string: "https://x")!, headers: [:], providerID: candidate.providerID, quality: nil, contentType: nil)
        }
        #expect(result?.candidate.providerID == "B")
    }

    @Test("never exceeds the budget")
    func budget() async {
        let candidates = (0..<5).map { SourceCandidate(providerID: "p\($0)", track: track("t", provider: "p\($0)")) }
        let service = SourceResolutionService(perPlayBudget: 2)
        var attempts = 0
        _ = await service.resolve(candidates: candidates) { _ in
            attempts += 1
            throw ProviderError.unavailable
        }
        #expect(attempts == 2)
    }

    @Test("cancellation returns no result")
    func cancellation() async {
        let candidates = [SourceCandidate(providerID: "A", track: track("t", provider: "A"))]
        let service = SourceResolutionService()
        let result = await service.resolve(candidates: candidates, resolve: { _ in
            PlaybackSource.remoteStream(url: URL(string: "https://x")!, headers: [:], providerID: "A", quality: nil, contentType: nil)
        }, isCancelled: { true })
        #expect(result == nil)
    }
}

@Suite("Next track preparation")
struct NextTrackPreparationTests {
    @Test("prepares past halfway on unmetered wifi")
    func prepares() {
        #expect(NextTrackPreparation.shouldPrepare(currentPosition: 60, duration: 100, hasNextTrack: true, isPreparing: false, isUnmeteredWiFi: true, isInBackground: false, nextIsNetwork: true))
    }

    @Test("does not prepare on cellular or in background")
    func guards() {
        #expect(!NextTrackPreparation.shouldPrepare(currentPosition: 60, duration: 100, hasNextTrack: true, isPreparing: false, isUnmeteredWiFi: false, isInBackground: false, nextIsNetwork: true))
        #expect(!NextTrackPreparation.shouldPrepare(currentPosition: 60, duration: 100, hasNextTrack: true, isPreparing: false, isUnmeteredWiFi: true, isInBackground: true, nextIsNetwork: true))
        #expect(!NextTrackPreparation.shouldPrepare(currentPosition: 60, duration: 100, hasNextTrack: true, isPreparing: true, isUnmeteredWiFi: true, isInBackground: false, nextIsNetwork: true))
        #expect(!NextTrackPreparation.shouldPrepare(currentPosition: 10, duration: 100, hasNextTrack: true, isPreparing: false, isUnmeteredWiFi: true, isInBackground: false, nextIsNetwork: true))
    }
}

@Suite("Source badge")
struct SourceBadgeTests {
    @Test("badge text for sources")
    func badge() {
        #expect(SourceBadge.text(providerID: "monochrome", quality: .lossless) == "HiFi · Lossless")
        #expect(SourceBadge.text(providerID: "local", quality: nil) == "Local")
    }
}

@Suite("Provider registry")
struct ProviderRegistryTests {
    @Test("order, enable and disable persist")
    func registry() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("providers.json")
        let p1 = FakeProvider(id: "a")
        let p2 = FakeProvider(id: "b")
        let registry = ProviderRegistry(providers: [p1, p2], fileURL: file)
        #expect(registry.enabledProviders().map(\.id) == ["a", "b"])
        registry.setEnabled("a", enabled: false)
        #expect(registry.enabledProviders().map(\.id) == ["b"])
        registry.move(from: 1, to: 0)
        // reload from disk
        let registry2 = ProviderRegistry(providers: [p1, p2], fileURL: file)
        #expect(registry2.all().first?.id == "b")
    }
}