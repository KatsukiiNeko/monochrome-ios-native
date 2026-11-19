<p align="center">
  <a href="https://github.com/KatsukiiNeko/monochrome-ios-native/actions/workflows/swift.yml?query=branch%3Adevelopment">
    <img src="https://img.shields.io/github/actions/workflow/status/KatsukiiNeko/monochrome-ios-native/swift.yml?branch=development&style=for-the-badge&logo=githubactions&label=CI" alt="CI status">
  </a>
  <img src="https://img.shields.io/badge/Platform-iOS%2017%2B-black?style=for-the-badge&logo=apple" alt="iOS 17 or later">
  <a href="license">
    <img src="https://img.shields.io/badge/License-Apache--2.0-blue?style=for-the-badge" alt="Apache 2.0 License">
  </a>
</p>

<p align="center">
  <a href="https://github.com/KatsukiiNeko/monochrome-ios-native">
    <img src="Branding/monochrome_logo.png" alt="Monochrome logo" width="140">
  </a>
</p>

<h1 align="center">Monochrome — Native iOS</h1>

<p align="center">
  <strong>A native, local-first music player for iPhone, built with SwiftUI and AVFoundation.</strong>
</p>

Monochrome streams a lossless catalog, plays your own files, and keeps playback,
history, favourites, playlists and downloads on the device. It is a native iOS
app inspired by the [Monochrome web app](https://github.com/monochrome-music/monochrome);
there is no WebView and no account.

## Features

**Playback**
- Native playback through `AVPlayer`: play/pause, previous/next, seeking, a
  reorderable queue, shuffle and repeat.
- A persistent mini-player and a full-screen Now Playing screen with artwork,
  synced lyrics, a queue sheet and output-route information.
- Lock Screen and Control Center metadata and remote controls, with accurate
  track, artist, album, duration and elapsed time.
- Session restore: the queue, position, shuffle and repeat survive a restart and
  come back paused.
- Sleep timer with 5, 15, 30, 45 and 60 minute options.

**Audio quality**
- Progressive FLAC from the catalog and lossless local files, reported as the
  decoder actually sees them.
- A format sheet with codec, sample rate, bit depth, channels, bitrate, the
  playback source (stream, cache, download, local file) and the active output
  route. Values measured from the loaded media are kept apart from catalog
  metadata, and unknown values are omitted rather than guessed.

**Sources**
- The Monochrome catalog: search, albums, artists, playback and downloads.
- Local files imported from the Files app, copied into the app's own storage.
- A YouTube Music companion source that only works when you run your own
  companion server; without one it is shown as unavailable. See
  [`docs/SOURCES.md`](docs/SOURCES.md).

**Library and offline**
- Favourites, recently played, and a local library with a five-entry rolling
  audio cache for streams.
- Permanent downloads with Vorbis tags and cover art written into the FLAC file.
- Separate cleanup paths for imported files, downloads and the cache.

**Discovery**
- On-device recommendations ("For You" and "Rediscover") from listening events,
  favourites and skips; no listening data leaves the device.
- Radio queues that replenish themselves as they run out.

**Playlists and podcasts**
- Local playlists with CSV, JSON and M3U import, uncertain-match review, and CSV
  or JSON export.
- Podcast search through the public Apple directory and episodes read from the
  show's own RSS feed.

**Lyrics**
- Time-synchronised or plain lyrics from [LRCLIB](https://lrclib.net), with
  tap-to-seek, pause-follow-while-scrolling, output-latency compensation and
  per-track timing offsets. See [`docs/LYRICS.md`](docs/LYRICS.md).

**Equalizer**
- Ten-band graphic equalizer and a parametric equalizer with up to sixteen
  bands, presets, preamp, bass, clarity, stereo width, Dynamic Boost and user
  presets. It reports when the current playback path cannot process audio
  instead of showing a dead control. See [`docs/EQ_RESEARCH.md`](docs/EQ_RESEARCH.md).

**Appearance**
- System, Light and Dark modes.
- Monochrome, Signal, Amber, Mint, Blue, Violet and Match Artwork accents.
- Imported runtime themes with contrast validation.

## Install

The release provides an **unsigned IPA**
(`Monochrome-<version>-unsigned.ipa`). It is not signed with an Apple
certificate, so iOS will not install it directly: sign it with your own
sideloading tool and your own Apple account first.

## Build from source

Requirements: Swift 6.x, Swift Package Manager, and iOS 17 or later for the app.
No third-party Swift packages are used.

```bash
swift test          # portable core tests, on Linux or macOS
scripts/build.sh    # arm64 iOS compile check, needs a Darwin Swift SDK
```

The iOS app itself is built and installed with the `xtool` workflow configured in
[`xtool.yml`](xtool.yml); device installs need your own signing and provisioning
setup. See [`docs/TOOLCHAIN_AUDIT.md`](docs/TOOLCHAIN_AUDIT.md) for the
Linux-to-iOS toolchain notes. Continuous integration runs `swift test` in
`swift:6.2` on `ubuntu-24.04`.

Useful extra check, only when you intend to contact the live catalog:

```bash
MONOCHROME_LIVE=1 swift test --filter LiveTracksAPITests
```

## Architecture

`MonochromeCore` is portable Swift (no SwiftUI, UIKit or AppKit) holding models,
services, playback state and persistence; `Monochrome` is the SwiftUI app layer
with the AVFoundation engine, audio session, Now Playing integration and views.
`PlayerController` is the single owner of playback state and the queue.
Permanent downloads are preferred over the cache, and the cache over the
network.

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [UI layout](docs/UI_LAYOUT.md)
- [Device test checklist](docs/DEVICE_TEST_CHECKLIST.md)
- [Source capabilities](docs/SOURCES.md)
- [Lyrics](docs/LYRICS.md)
- [Equalizer research](docs/EQ_RESEARCH.md)
- [Toolchain audit](docs/TOOLCHAIN_AUDIT.md)
- [Feature gap against the web app](docs/FEATURE_GAP.md)
- [Repository migration and attribution](docs/REPO_MIGRATION.md)

## Content and distribution notice

The catalog is Tidal-derived and its audio is relayed by a third-party host.
The Apache-2.0 license covers this source code only; it gives no rights to
third-party recordings, metadata or artwork, and availability of a source is not
permission to redistribute it. Check the applicable service terms and content
rights before publishing builds.

## License

[Apache License 2.0](license), with attribution in [`NOTICE`](NOTICE) and
[`Branding/SOURCE.md`](Branding/SOURCE.md). The app is a native derivative of
[monochrome-music/monochrome](https://github.com/monochrome-music/monochrome)
and is independently maintained.
