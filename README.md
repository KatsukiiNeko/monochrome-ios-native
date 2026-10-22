# Monochrome (native iOS)

A small SwiftUI music player rebuilt from the [Monochrome](https://github.com/monochrome-music/monochrome)
web app. It plays audio files you import from the Files app, with a library,
queue, favorites, artwork and Lock Screen controls. No account, no network, no
tracking.

This is a **compile-tested** project: it was written and built on Linux against
the iOS SDK, but it has never been installed or run on a device.

## What works

| Feature | Status | Verification |
|---|---|---|
| Import audio from the Files app (copied into app storage) | implemented | **L1** compile only |
| Library persisted as JSON, tolerant of missing fields | implemented | **L2** host tests |
| Remove a track (app copy only; original untouched) | implemented | **L2** host tests |
| Playback controls, queue, next/previous, seek | implemented | **L2** state machine tests |
| Favorites, persisted as JSON | implemented | **L2** host tests + **L1** UI |
| Queue screen: jump, reorder, remove | implemented | **L1** compile only |
| Embedded artwork in the player | implemented | **L1** compile only; tag reading unverified |
| Audio session, background audio mode, Now Playing, remote commands, interruptions, route changes | implemented | **L1** compile only — **not** verified on a device |
| Streaming / search / lyrics / playlists / accounts | **not implemented** | see “Streaming” below |

Verification levels: **L1** compiles for iOS, **L2** unit-tested on Linux,
**L3** verified against a live service, **L4** verified on a device (not reached).

## Streaming: deliberately not implemented

The upstream web app plays `https://tracks.monochrome.st/track/<id>` — an
unauthenticated relay of Tidal-derived audio. It responds with real FLAC bytes
(HTTP 206, `fLaC` magic, ~40 MB per track) and works from `curl`, but it is an
unofficial mirror of a commercial catalog with no license or terms, so a new
client streaming from it would not be legitimate. The official iOS app instead
resolves Tidal ISRCs through Qobuz instances, which has the same problem.

The full evidence and the rejected alternative are in
[`docs/STREAMING_FEASIBILITY.md`](docs/STREAMING_FEASIBILITY.md). `MusicService`
is the seam where a future, licensed catalog client would plug in.

## Requirements

- Linux (tested on x86_64), Swift 6.4 via swiftly
- xtool 1.22 with the Darwin Swift SDK (`darwin`, `iPhoneOS27.1.sdk`)
- No Xcode, no third-party packages

## Build and test

```bash
swift test        # portable core tests, run on Linux (44 tests)
scripts/build.sh  # compile-check for iOS; never installs or signs
```

`scripts/build.sh` runs:

```bash
swift build --build-system native --swift-sdk darwin --triple arm64-apple-ios
```

`--build-system native` is required: SwiftPM 6.4's default SwiftBuild engine
cannot resolve the `iphoneos` platform on this host.

There is no `xtool build`; the only xtool command that packages an app is
`xtool dev`, which also installs it, so this repository never runs it. The
bundle id in `the local xtool manifest` (`com.neko-ngtran.monochrome`) is a personal identifier
for local device runs; change it before any distribution.

## Repository layout

```
Package.swift              two targets, Swift 6
the local xtool manifest                  bundle id + Info.plist path for xtool packaging
Resources/Info.plist       display name, background audio mode
scripts/build.sh           the iOS compile check
Sources/MonochromeCore/    portable: models, library, queue, player state machine
  Track.swift              track model (tolerant Codable)
  LibraryStore.swift       library.json read/write (atomic)
  FavoritesStore.swift     favorites.json read/write
  MusicService.swift       MusicService + TrackMetadata + TrackMetadataReading seams
  LocalFileService.swift   import (copy into app storage), list, delete
  Queue.swift              cursor over an ordered track list
  PlayerController.swift   @Observable state machine and commands
  PlaybackEngine.swift     engine protocol (load/play/pause/seek/stop + events)
  PlaybackState.swift      idle/loading/playing/paused/failed
  DurationFormatting.swift m:ss and h:mm:ss
Sources/Monochrome/        iOS-only: SwiftUI views + AVFoundation
  App.swift                @main
  AppModel.swift           library + import flow + player wiring
  ContentView.swift        library list, import, mini player host
  MiniPlayerView.swift     compact bar
  PlayerView.swift         full player (artwork, seek, transport, errors)
  QueueView.swift          queue management
  ArtworkView.swift        embedded artwork or placeholder
  AVPlayerEngine.swift     AVPlayer implementation of PlaybackEngine
  AudioSessionController.swift  category, interruptions, route changes
  NowPlayingController.swift    Lock Screen metadata and remote commands
  MetadataReader.swift     title/artist/album/duration/artwork tags
  CallbackRelay.swift      main-actor hop for framework callbacks
Tests/MonochromeCoreTests/ host tests + JSON fixture
docs/                      audits, toolchain, streaming, plan, progress
```

## Behavior notes

- Imported files are **copied** into `Application Support/Monochrome/Media`.
  Deleting a track removes that copy; your original file in Files is untouched.
- The library and favorites are plain JSON files next to the media directory.
  A corrupt library shows an error instead of crashing; unknown/missing fields
  fall back to defaults.
- The app is dark-only and uses system colors, Dynamic Type and VoiceOver labels.

## Limitations / not tested

- Nothing has been run on hardware. Playback, background audio, Lock Screen,
  interruptions and route changes are compile-checked only; they may need fixes.
- Artwork extraction depends on the file carrying tags AVFoundation can read.
  FLAC tag coverage is unverified.
- No recents/history screen, no playlists, no lyrics, no album/artist pages.
- No remote sync; everything is local.

## License

Apache-2.0. This is a derivative work of the Monochrome project; see
[`license`](license) and [`NOTICE`](NOTICE).
