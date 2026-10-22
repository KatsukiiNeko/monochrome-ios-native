# Implementation plan (M5–M12)

Refined from the M1–M3 evidence: **Path B, local files** (see
`docs/STREAMING_FEASIBILITY.md`), two targets (see `docs/TOOLCHAIN_AUDIT.md`),
no third-party dependencies, no asset catalogs.

Verification levels: L1 = iOS compile, L2 = host `swift test`, L3 = live check.
Nothing reaches L4 (no device in this run).

## M5 · Clean the root

Delete the web app and its tooling and the untracked nested iOS project, in three
reviewed commits. Keep `license`, `.git`, remotes and the Apache-2.0 text; add a
short `NOTICE` crediting the upstream project. Acceptance: root contains only the
native project, `git remote -v` unchanged, `~/monochrome-backup-20261022-1234.tar.gz`
and `~/monochrome-reference/` still hold everything removed.

## M6 · Scaffold

`Package.swift` (two targets, Swift 6), `the local xtool manifest` (`version: 1`,
`bundleID: com.example.monochrome`, `infoPath`), `Sources/MonochromeCore/`,
`Sources/Monochrome/`, `Tests/`, `Resources/Info.plist` with
`UIBackgroundModes: [audio]`, `.gitignore`, `scripts/build.sh`, README stub.
Acceptance: `scripts/build.sh` green (L1) and `swift test` green with one real
test (L2).

## M7 · Data layer

- `Track` (id, title, artist, album, duration, file name) + `PlaybackState`.
- `MusicService` protocol: list / import / delete. `LocalFileService` copies picked
  files into Application Support and persists a `library.json`.
- `LibraryStore`: Codable JSON, atomic write, tolerant of unknown/missing fields.
- `TrackMetadata` protocol (title/artist/album/duration) so the copy+persist logic
  is host-testable; the AVFoundation reader lives in the iOS layer.
- Tests use a sanitized fixture of the app's own `library.json`.
- Acceptance: import/list/delete round-trip tests pass (L2), iOS build green (L1).

## M8 · Player core

`PlaybackEngine` protocol (`load`, `play`, `pause`, `seek`, `stop`, events
`ready/finished/failed/position`); `Queue` (append, remove, next, previous,
jump); `PlayerController` (`@MainActor @Observable`): idle → loading → playing ⇄
paused → failed, queue advance on finish, error message on failure.
Acceptance: fake-engine tests cover every transition, queue edge cases (empty,
last track, removing current) pass (L2), iOS build green (L1).

## M9 · AVPlayer + UI

`AVPlayerEngine` (AVPlayer + periodic time observer + item-ended/failed
notifications), `MetadataReader` (AVURLAsset metadata), `fileImporter` import,
library list, mini player, full player (play/pause, seek slider, title/artist,
loading and error states), dark monochrome styling, Dynamic Type, accessibility
labels. Acceptance: L1 build; no device verification.

## M10 · System integration

`AVAudioSession` `.playback` + `.activate` on first play, `UIBackgroundModes`
audio, `MPNowPlayingInfoCenter`, `MPRemoteCommandCenter` (play/pause/next/prev/seek),
interruption and route-change handling (pause on old-device-unavailable).
Compile-checked only (L1). Background/Lock Screen behavior explicitly untested.

## M11 · Extras, value order, one commit each

1. Queue screen (reorder, remove, jump).
2. Recents + favorites persisted as JSON in Application Support.
3. Artwork from embedded metadata (if the metadata reader yields it).
Lyrics/album/artist pages are dropped: no backend (Path B).

## M12 · Finalize

README with feature/verification matrix, repository layout, exact commands,
limitations; the contributor rules synced; PROGRESS.md truthful; final `git status`; handoff.

## Risks

- `content-type: application/octet-stream` on the rejected remote path would have
  needed an on-device AVPlayer check — moot for Path B.
- iOS-only code cannot be exercised here; a compile is the ceiling.
- `swift test` must keep passing while the iOS target builds empty on Linux; any
  Apple-only file needs the `#if canImport(SwiftUI)` guard.
