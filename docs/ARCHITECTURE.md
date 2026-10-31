# Architecture

## Two layers

| Layer | Target | Imports | Tested on |
|---|---|---|---|
| `MonochromeCore` | portable | `Foundation`, `FoundationNetworking`, `Observation` | Linux (host tests) |
| `Monochrome` | iOS | `MonochromeCore`, `SwiftUI`, `AVFoundation`, `MediaPlayer`, `os`, `UIKit`, `CoreGraphics`, `ImageIO`, `UniformTypeIdentifiers`, `AVKit`, `MediaToolbox` | iOS device / cross-compile |

`MonochromeCore` must not import Apple-only frameworks. A host test (`CoreLayeringTests`) enforces this by scanning the core sources for imports outside the allowed set.

## Playback order

`PlayerController` resolves the current track in this order:

1. **Downloaded file** — if the track is marked downloaded and the file exists under `Application Support/Downloads`.
2. **Cache hit** — if the track is in the on-disk LRU cache (`AudioCache`), five songs, evicts least-recently-used.
3. **Network** — `TrackURLResolver` asks the catalog for a progressive FLAC URL, `AVPlayerEngine` loads it.

If a downloaded or cached file fails to play, the controller falls through to the next source automatically.

## Sources model

`MusicSourceID` identifies a catalog. Each source declares `SourceCapabilities` (`search`, `stream`, `downloads`).

- `monochrome` — the public progressive FLAC endpoint. Supports all three capabilities.
- `youTubeMusic` — companion-server design, no default URL, `needsSetup` until the user configures a server. Supports `search` and `stream` only.

The app currently wires only `monochrome`. The YouTube path is scaffolded but not connected to a live server.

## Persistence

| What | Format | Location |
|---|---|---|
| Streaming endpoint, enabled toggle | UserDefaults | `streaming.baseURL`, `streaming.enabled` |
| Appearance, accent, lyrics timing | UserDefaults | `appearance.mode`, `accent.preference`, `lyrics.timingDelay.<track>` |
| Favorites | JSON (v1 legacy IDs, v2 full tracks) | `Application Support/favorites.json` |
| History | JSON | `Application Support/history.json` |
| Library index | JSON | `Application Support/library.json` |
| EQ settings + user presets | JSON (schema versioned) | `Application Support/eq-settings.json` |
| Download index | JSON | `Application Support/Downloads/index.json` |
| Cache | flat files + directory scan | `Caches/AudioCache/` |

All JSON decoders are tolerant: missing fields get defaults, unknown fields are ignored, and schema versions allow forward migration. Fixtures in `Tests/MonochromeCoreTests/Fixtures/` decode the exact shapes written by v0.3.0.

## Adding a feature

1. Model and pure logic in `MonochromeCore` with host tests (`swift test` on Linux).
2. Wire the iOS integration in `Monochrome` — views bind to published state, send intents to the controller.
3. If it needs iOS-only frameworks (AVFoundation, MediaPlayer, etc.), keep that code behind `#if canImport(...)` or in the `Monochrome` target.
4. Run `scripts/build.sh` to verify the iOS cross-compile.
5. Run `swift test` to verify the core behavior.