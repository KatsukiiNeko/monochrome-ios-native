<p align="center">
  <a href="https://github.com/KatsukiiNeko/monochrome-ios-native">
    <img src="Branding/monochrome_logo.png" alt="Monochrome logo" width="140">
  </a>
</p>

<h1 align="center">Monochrome — Native iOS</h1>

<p align="center">
  <strong>A native, local-first music player for iPhone, built with SwiftUI and AVFoundation.</strong>
</p>

<p align="center">
  <a href="https://github.com/KatsukiiNeko/monochrome-ios-native/releases">
    <img src="https://img.shields.io/github/v/release/KatsukiiNeko/monochrome-ios-native?include_prereleases&sort=semver&style=for-the-badge&logo=github&label=Version" alt="Latest release version">
  </a>
  <img src="https://img.shields.io/badge/Platform-iOS%2017%2B-black?style=for-the-badge&logo=apple" alt="iOS 17 or later">
  <img src="https://img.shields.io/badge/Swift-6.4.1-F05138?style=for-the-badge&logo=swift&logoColor=white" alt="Swift 6">
  <a href="license">
    <img src="https://img.shields.io/badge/License-Apache--2.0-blue?style=for-the-badge" alt="Apache 2.0 License">
  </a>
</p>

<p align="center">
  <a href="#features">Features</a> ·
  <a href="#install">Install</a> ·
  <a href="#build-from-source">Build</a> ·
  <a href="#architecture">Architecture</a> ·
  <a href="#documentation">Documentation</a> ·
  <a href="#license">License</a>
</p>

---

## Overview

Monochrome streams a lossless catalog, plays your own files, and keeps playback,
history, favourites, playlists and downloads on the device. It is a native iOS
app inspired by the [Monochrome web app](https://github.com/monochrome-music/monochrome):
no WebView, no account and no third-party Swift packages.

| | |
|---|---|
| **Lossless first** | Progressive FLAC streaming, lossless local files and tagged FLAC downloads. |
| **Local-first** | Queue, history, library and recommendations are stored and computed on the device. |
| **Truly native** | SwiftUI interface on an `AVPlayer` engine, with full Lock Screen and Control Center integration. |
| **Honest audio info** | Format details come from the decoder, not guesses; unknown values are left out. |

## Features

### Playback

- Native playback through `AVPlayer`: play/pause, previous/next, seeking, a
  reorderable queue, shuffle and repeat.
- Persistent mini-player and a full-screen Now Playing screen with artwork,
  synced lyrics, a queue sheet and output-route information.
- Lock Screen and Control Center metadata and remote controls, with accurate
  track, artist, album, duration and elapsed time.
- Session restore: queue, position, shuffle and repeat survive a restart and
  return paused.
- Sleep timer with 5, 15, 30, 45 and 60 minute options.

### Audio quality

- Progressive FLAC from the catalog and lossless local files, reported as the
  decoder actually sees them.
- A format sheet showing codec, sample rate, bit depth, channels, bitrate, the
  playback source (stream, cache, download or local file) and the active output
  route. Values measured from the loaded media are kept separate from catalog
  metadata.

### Sources

| Source | What it provides | Requirement |
|---|---|---|
| **Monochrome catalog** | Search, albums, artists, playback and downloads | None |
| **Local files** | Files imported from the Files app, copied into the app's own storage | None |
| **YouTube Music companion** | Optional additional source | Your own companion server; shown as unavailable without one |

See [`docs/SOURCES.md`](docs/SOURCES.md) for per-source capabilities.

### Library and offline

- Favourites, recently played and a local library.
- A five-entry rolling audio cache for streams.
- Permanent downloads with Vorbis tags and cover art written into the FLAC file.
- Separate cleanup paths for imported files, downloads and the cache.

### Discovery

- On-device recommendations ("For You" and "Rediscover") built from listening
  events, favourites and skips. No listening data leaves the device.
- Radio queues that replenish themselves as they run out.

### Playlists and podcasts

- Local playlists with CSV, JSON and M3U import, uncertain-match review, and CSV
  or JSON export.
- Podcast search through the public Apple directory, with episodes read from the
  show's own RSS feed.

### Lyrics

- Time-synchronised or plain lyrics from [LRCLIB](https://lrclib.net), with
  tap-to-seek, pause-follow-while-scrolling, output-latency compensation and
  per-track timing offsets. See [`docs/LYRICS.md`](docs/LYRICS.md).

### Equalizer

- Ten-band graphic equalizer and a parametric equalizer with up to sixteen
  bands, presets, preamp, bass, clarity, stereo width, Dynamic Boost and user
  presets.
- Reports when the current playback path cannot process audio instead of
  showing a dead control. See [`docs/EQ_RESEARCH.md`](docs/EQ_RESEARCH.md).

### Appearance

- System, Light and Dark modes.
- Monochrome, Signal, Amber, Mint, Blue, Violet and Match Artwork accents.
- Imported runtime themes with contrast validation.

## Install

Each [release](https://github.com/KatsukiiNeko/monochrome-ios-native/releases)
ships an **unsigned IPA** (`Monochrome-<version>-unsigned.ipa`). It is not signed
with an Apple certificate, so iOS will not install it directly.

1. Download the IPA from the latest release.
2. Sign it with your own sideloading tool and your own Apple account.
3. Install the signed app on your iPhone (iOS 17 or later).

## Build from source

| Requirement | Version |
|---|---|
| Swift | 6.x with Swift Package Manager |
| iOS deployment target | 17 or later |
| Third-party Swift packages | None |

```bash
swift test          # portable core tests, on Linux or macOS
scripts/build.sh    # arm64 iOS compile check, needs a Darwin Swift SDK
```

The iOS app itself is built and installed with the `xtool` workflow configured in
[`xtool.yml`](xtool.yml). Device installs need your own signing and provisioning
setup; see [`docs/TOOLCHAIN_AUDIT.md`](docs/TOOLCHAIN_AUDIT.md) for the
Linux-to-iOS toolchain notes.

Continuous integration runs `swift test` in `swift:6.2` on `ubuntu-24.04`.

To also exercise the live catalog (network access required):

```bash
MONOCHROME_LIVE=1 swift test --filter LiveTracksAPITests
```

## Architecture

| Module | Responsibility |
|---|---|
| `MonochromeCore` | Portable Swift with no SwiftUI, UIKit or AppKit: models, services, playback state and persistence. |
| `Monochrome` | The SwiftUI app layer: AVFoundation engine, audio session, Now Playing integration and views. |

`PlayerController` is the single owner of playback state and the queue. Source
priority at playback time is: permanent downloads, then the cache, then the
network.

Details are in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Documentation

| Document | Topic |
|---|---|
| [Architecture](docs/ARCHITECTURE.md) | Module boundaries and playback ownership |
| [UI layout](docs/UI_LAYOUT.md) | Screen structure and navigation |
| [Device test checklist](docs/DEVICE_TEST_CHECKLIST.md) | Manual verification on a real device |
| [Source capabilities](docs/SOURCES.md) | What each source can and cannot do |
| [Lyrics](docs/LYRICS.md) | Lyrics providers, sync and timing offsets |
| [Equalizer research](docs/EQ_RESEARCH.md) | EQ design and processing limits |
| [Toolchain audit](docs/TOOLCHAIN_AUDIT.md) | Linux-to-iOS build notes |
| [Feature gap](docs/FEATURE_GAP.md) | Comparison against the web app |
| [Repository migration](docs/REPO_MIGRATION.md) | Migration and attribution history |

## Content and distribution notice

> [!IMPORTANT]
> The catalog is Tidal-derived and its audio is relayed by a third-party host.
> The Apache-2.0 license covers this source code only. It grants no rights to
> third-party recordings, metadata or artwork, and availability of a source is
> not permission to redistribute it. Check the applicable service terms and
> content rights before publishing builds.

## License

Released under the [Apache License 2.0](license), with attribution in
[`NOTICE`](NOTICE) and [`Branding/SOURCE.md`](Branding/SOURCE.md).

Monochrome Native is a derivative of
[monochrome-music/monochrome](https://github.com/monochrome-music/monochrome)
and is independently maintained.
