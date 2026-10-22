# Monochrome (native iOS)

A SwiftUI music player rebuilt from the [Monochrome](https://github.com/monochrome-music/monochrome)
web app. It plays audio files you import from the Files app **and** streams from
the same public catalog the web app uses, with Home, Search and Library tabs, a
persistent mini player, a full Now Playing screen, a queue, favorites, play
history and Lock Screen controls. No account, no tracking.

This is a **compile-tested** project: it was written and built on Linux against
the iOS SDK, but it has never been installed or run on a device.

## What works

| Feature | Status | Verification |
|---|---|---|
| Import audio from the Files app (copied into app storage) | implemented | **L1** compile only |
| Library persisted as JSON, tolerant of missing fields | implemented | **L2** host tests |
| Remove a track (app copy only; original untouched) | implemented | **L2** host tests |
| Playback controls, queue, next/previous, seek | implemented | **L2** state machine tests |
| Favorites (local and streamed tracks), persisted as JSON | implemented | **L2** host tests + **L1** UI |
| Recently played list | implemented | **L2** host tests + **L1** UI |
| Catalog search: tracks, albums, artists | implemented | **L3** live request + **L2** fake-HTTP tests |
| Stream a track (resolve at play time, one retry) | implemented | **L3** live bytes + **L2** tests |
| Album and artist detail sheets with playable tracks | implemented | **L3** live request + **L1** UI |
| Host failover with short timeouts and session health | implemented | **L2** fake-HTTP tests |
| Configurable streaming host / offline mode | implemented | **L2** tests + **L1** UI |
| Tab shell, mini player, Now Playing, queue | implemented | **L1** compile only |
| Audio session, background audio, Now Playing info, remote commands, interruptions, route changes | implemented | **L1** compile only — **not** verified on a device |
| App icon from the web app, unchanged | wired via `iconPath` | file-level evidence only — packing unverified |
| Lyrics, playlists, accounts, sync | **not implemented** | — |

Verification levels: **L1** compiles for iOS, **L2** unit-tested on Linux,
**L3** verified against a live service, **L4** verified on a device (not reached).

## Streaming

The web app plays `https://tracks.monochrome.st/track/<id>`: an unauthenticated,
progressive FLAC stream that the app resolves at play time. The native app uses
that same public endpoint (Path A) as its default host, with a truthful
`User-Agent`, no `Origin`/`Referer` spoofing, no credentials, and no access to
the token-gated `/api/v2/track/` path.

Quality ceiling: **FLAC 16-bit / 44.1 kHz** (`LOSSLESS`). The website's
`HI_RES_LOSSLESS` tier is not exposed by this endpoint.

**Read before distributing:** the catalog is Tidal-derived and relayed by a
third-party host. The upstream repository carries no terms of service and no
content licence — its Apache-2.0 licence covers the source code only. A personal
build and a published app are different things; see
[`docs/ONLINE_STREAMING_AUDIT.md`](docs/ONLINE_STREAMING_AUDIT.md).

Settings accepts a different HTTPS host (for example your own instance or a paid
endpoint, as the upstream README describes) or an empty value, which turns
streaming off and leaves local playback intact.

## Requirements

- Linux (tested on x86_64), Swift 6.4 via swiftly
- xtool 1.22 with the Darwin Swift SDK (`darwin`, `iPhoneOS27.1.sdk`)
- No Xcode, no third-party packages

## Build and test

```bash
swift test        # portable core tests, run on Linux (73 tests)
scripts/build.sh  # compile-check for iOS; never installs or signs
```

`scripts/build.sh` runs:

```bash
swift build --build-system native --swift-sdk darwin --triple arm64-apple-ios
```

`--build-system native` is required: SwiftPM 6.4's default SwiftBuild engine
cannot resolve the `iphoneos` platform on this host.

A live check of the catalog is opt-in and never part of the default test run:

```bash
MONOCHROME_LIVE=1 swift test --filter LiveTracksAPITests
```

It searches the real catalog, resolves a stream and asserts the response starts
with the FLAC magic bytes.

There is no `xtool build`; the only xtool command that packages an app is
`xtool dev`, which also installs it, so this repository never runs it. The
bundle id in the local xtool project manifest (`com.neko-ngtran.monochrome`) is
a personal identifier for local device runs; change it before any distribution.

## Repository layout

```
Package.swift              two targets, Swift 6
Resources/Info.plist       display name, background audio mode
Branding/                  the web app's icon and logo, unchanged (see SOURCE.md)
scripts/build.sh           the iOS compile check
Sources/MonochromeCore/    portable: models, stores, API client, player state machine
  Track.swift              track model, local or streamed (tolerant Codable)
  LibraryStore.swift       library.json read/write (atomic)
  FavoritesStore.swift     favorite tracks (migrates the v1 id-only file)
  HistoryStore.swift       recently played, capped
  MusicService.swift       MusicService + metadata seams
  LocalFileService.swift   import (copy into app storage), list, delete
  HTTPClient.swift         HTTP seam + URLSession implementation
  TracksAPIClient.swift    catalog search/detail/stream URLs, host failover
  TrackURLResolver.swift   local file or stream URL, resolved at play time
  StreamingSettings.swift  chosen host in UserDefaults
  Queue.swift              cursor over an ordered track list
  PlayerController.swift   @Observable state machine and commands
  PlaybackEngine.swift     engine protocol
  PlaybackState.swift      idle/loading/playing/paused/failed
  DurationFormatting.swift m:ss and h:mm:ss
Sources/Monochrome/        iOS-only: SwiftUI views + AVFoundation
  App.swift                @main
  AppModel.swift           library, catalog, favorites, history, player wiring
  ContentView.swift        tab shell and mini player placement
  HomeView.swift           greeting, recents, favorites
  SearchView.swift         debounced search for tracks/albums/artists
  CatalogDetailViews.swift album and artist sheets
  LibraryView.swift        imported files and favorites
  PlayerView.swift         full-screen Now Playing
  MiniPlayerView.swift     compact bar
  QueueView.swift          queue management
  TrackRow.swift           shared track row
  TrackArtwork.swift       remote, local or placeholder artwork
  Theme.swift              spacing + the single glass availability gate
  SettingsView.swift       streaming host
  AVPlayerEngine.swift     AVPlayer implementation of PlaybackEngine
  AudioSessionController.swift  category, interruptions, route changes
  NowPlayingController.swift    Lock Screen metadata and remote commands
  MetadataReader.swift     title/artist/album/duration/artwork tags
  CallbackRelay.swift      main-actor hop for framework callbacks
Tests/MonochromeCoreTests/ host tests + JSON fixtures
docs/                      audits, toolchain, plan, migration, progress
```

## Behavior notes

- Imported files are **copied** into `Application Support/Monochrome/Media`.
  Deleting a track removes that copy; your original file in Files is untouched.
- The library, favorites and history are plain JSON files next to the media
  directory. A corrupt library shows an error instead of crashing; unknown or
  missing fields fall back to defaults.
- Stream URLs are never saved: the app builds one from the catalog id at play
  time, and if playback fails it resolves once more before showing Retry.
- The app is dark-only and uses system colors, Dynamic Type and VoiceOver labels.

## Needs eyes on a device

1. Whether `AVPlayer` accepts the host's `application/octet-stream` FLAC. This is
   the biggest unknown; if it refuses, streaming needs a different host.
2. Mini player placement: iOS 26.1 uses `tabViewBottomAccessory`; everything else
   falls back to a bottom inset. Check it never covers list content.
3. Glass button legibility over bright artwork, and with Reduce Transparency on.
4. Artwork and Now Playing layout at the largest Dynamic Type sizes and on a
   small phone.
5. Background audio, Lock Screen metadata and remote commands after the
   navigation rewrite.
6. That the Home logo resource (declared in the local xtool manifest) is packaged, and that
   the icon appears on the Home Screen.
7. Remote artwork over a slow connection (placeholder, then fade).
8. That shuffling/next/previous keep working while browsing tabs.

## License

Apache-2.0. This is a derivative work of the Monochrome project; see
[`license`](license) and [`NOTICE`](NOTICE). The icon and logo are the upstream
project's branding, included unchanged; see `Branding/SOURCE.md`.
