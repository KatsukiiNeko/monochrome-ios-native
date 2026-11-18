<p align="center">
  <a href="https://github.com/KatsukiiNeko/monochrome-ios-native/actions/workflows/swift.yml?query=branch%3Adevelopment">
    <img src="https://img.shields.io/github/actions/workflow/status/KatsukiiNeko/monochrome-ios-native/swift.yml?branch=development&style=for-the-badge&logo=githubactions&label=CI" alt="CI status">
  </a>
  <img src="https://img.shields.io/badge/Swift-6.x-F05138?style=for-the-badge&logo=swift&logoColor=white" alt="Swift 6">
  <img src="https://img.shields.io/badge/Framework-SwiftUI-blue?style=for-the-badge&logo=swift" alt="SwiftUI">
  <img src="https://img.shields.io/badge/Platform-iOS%2017%2B-black?style=for-the-badge&logo=apple" alt="iOS 17 or later">
  <a href="license">
    <img src="https://img.shields.io/badge/License-Apache--2.0-blue?style=for-the-badge" alt="Apache 2.0 License">
  </a>
</p>

<p align="center">
  <a href="https://github.com/KatsukiiNeko/monochrome-ios-native">
    <img src="Branding/monochrome_logo.png" alt="Monochrome logo" width="150">
  </a>
</p>

<h1 align="center">Monochrome — Native iOS</h1>

<p align="center">
  <strong>A native, local-first music player built with SwiftUI.</strong>
</p>

<p align="center">
  Discover music, stream progressive FLAC, manage an offline library, and control playback through a native iOS interface.
</p>

<p align="center">
  <a href="https://github.com/KatsukiiNeko/monochrome-ios-native">Repository</a> ·
  <a href="https://github.com/KatsukiiNeko/monochrome-ios-native/tree/development/docs">Documentation</a> ·
  <a href="https://github.com/KatsukiiNeko/monochrome-ios-native/issues">Issues</a> ·
  <a href="license">License</a>
</p>

<p align="center">
  <a href="https://github.com/KatsukiiNeko/monochrome-ios-native/stargazers">
    <img src="https://img.shields.io/github/stars/KatsukiiNeko/monochrome-ios-native?style=for-the-badge&color=ffffff&labelColor=000000" alt="GitHub stars">
  </a>
  <a href="https://github.com/KatsukiiNeko/monochrome-ios-native/forks">
    <img src="https://img.shields.io/github/forks/KatsukiiNeko/monochrome-ios-native?style=for-the-badge&color=ffffff&labelColor=000000" alt="GitHub forks">
  </a>
  <a href="https://github.com/KatsukiiNeko/monochrome-ios-native/issues">
    <img src="https://img.shields.io/github/issues/KatsukiiNeko/monochrome-ios-native?style=for-the-badge&color=ffffff&labelColor=000000" alt="GitHub issues">
  </a>
</p>

---

## What is Monochrome?

**Monochrome Native** is an independently maintained iOS music player inspired by the [Monochrome web app](https://github.com/monochrome-music/monochrome). It brings the project to iPhone as a native SwiftUI application rather than embedding the web interface in a WebView.

The app combines an online music catalog with local audio, persistent playback, offline downloads, lyrics, playlists, recommendations, radio, and podcasts. Its design is local-first: the library, favorites, history, playlists, playback state, and listening profile are stored on the device.

The project does not require an account for its documented public catalog path. It ships without analytics or tracking SDKs and has no third-party Swift package dependencies.

> **Project lineage:** This repository is a native iOS derivative of [monochrome-music/monochrome](https://github.com/monochrome-music/monochrome). It is independently maintained. See [`docs/REPO_MIGRATION.md`](docs/REPO_MIGRATION.md), [`NOTICE`](NOTICE), [`Branding/SOURCE.md`](Branding/SOURCE.md), and [`license`](license) for migration history, attribution, branding provenance, and license terms.

## Features

### Music discovery

- Search the Monochrome catalog for tracks, albums, and artists.
- Browse album tracklists and artist releases.
- View artist biographies, external links, and social links when supplied by the catalog.
- Search results and provider capabilities are handled through the source-provider layer.

### Playback

- Native playback powered by AVFoundation and `AVPlayer`.
- Persistent mini-player and a dedicated Now Playing screen.
- Queue management, seeking, previous/next, shuffle, and repeat modes.
- Lock Screen and system media controls through Now Playing integration.
- AirPlay route selection and output-route information.
- Session restoration for queue, playback position, shuffle, and repeat state. Restored sessions remain paused rather than starting audio automatically.
- Sleep timer with 5, 15, 30, 45, or 60-minute options.

### Library and offline listening

- Import audio from the iOS Files app. Imported files are copied into the app's storage; removing an in-app item does not delete the original file.
- Keep favorites, recently played history, and a local music library on-device.
- Save supported tracks as permanent downloads for offline playback.
- Maintain a separate five-track rolling LRU audio cache for recently played streams.
- Keep imported files, permanent downloads, and temporary cache entries in separate storage locations and cleanup paths.

### Audio information and equalizer

- Show the available codec, container, sample rate, bit depth, channel count, bitrate, playback source, and active output route.
- Distinguish values measured from the loaded media from values reported by catalog metadata. Unknown values are omitted instead of guessed; bitrate is identified as estimated when applicable.
- Provide a ten-band graphic equalizer and a parametric equalizer with up to sixteen bands.
- Include filter types, built-in presets, preamp control, bass, clarity, stereo width, Dynamic Boost, and user presets.
- Report equalizer availability based on the current playback path rather than presenting an inactive control as functional.

See [`docs/EQ_RESEARCH.md`](docs/EQ_RESEARCH.md) for implementation notes and current limitations.

### Lyrics

- Retrieve plain or time-synchronised lyrics from [LRCLIB](https://lrclib.net) when the Lyrics view is opened.
- Follow synced lines during playback and seek by selecting a line.
- Pause automatic following while the listener scrolls, with an option to resume following.
- Apply output-route latency compensation and per-track manual timing adjustments.
- Present explicit loading, instrumental, not-found, offline, and error states.

See [`docs/LYRICS.md`](docs/LYRICS.md).

### Playlists, recommendations, and radio

- Create and manage local playlists.
- Import playlists from CSV or JSON, review uncertain track matches, and resume an interrupted import.
- Export playlists as CSV or JSON. Exporting a downloaded FLAC also writes its tags and cover artwork.
- Generate on-device recommendations from listening events, favorites, skips, and downloads.
- Start a radio queue from a track or artist and let it replenish as the queue approaches its end.

### Podcasts

- Search the public Apple podcast directory.
- Browse shows and retrieve episodes from each show's HTTPS RSS feed.
- Play podcast episodes through the shared player.

### Preferences and privacy

- System, Light, and Dark appearance modes.
- Monochrome, Signal, Amber, Mint, Blue, Violet, and Match Artwork accent options.
- Enable or disable the online endpoint while retaining local playback.
- Configure or reset the catalog endpoint, clear the temporary cache, and manage permanent downloads.
- No embedded service credentials, account system, analytics SDK, or tracking SDK.

## Music sources

The app models providers by their actual capabilities. An unavailable integration is not presented as a working service.

| Source | Search and browse | Playback | Permanent downloads | Availability |
|---|---|---|---|---|
| Monochrome catalog | Tracks, albums, and artists | Progressive FLAC | Supported | Configured by default |
| Local files | On-device library | Local audio files | Managed as imported files | Available after importing files |
| YouTube Music companion | Requires a user-configured companion server | Requires a user-configured companion server | Not supported | No server is configured in this build |

The YouTube Music integration does not scrape pages, extract audio, use cookies, or call a direct YouTube API. Its supported design is a user-run HTTPS companion service; without a configured server, it remains unavailable. See [`docs/SOURCES.md`](docs/SOURCES.md).

## Streaming and audio quality

The default Monochrome catalog uses the public progressive stream endpoint:

```text
https://tracks.monochrome.st/track/<track-id>
```

The repository's current service audit documents this endpoint as a progressive FLAC stream in the `LOSSLESS` tier, with a **16-bit / 44.1 kHz** format. The audited path does not expose the website's `HI_RES_LOSSLESS` tier. The native client does not call the token-gated `/api/v2/track/` endpoint.

The Audio sheet reports the format AVFoundation exposes for the loaded media. It can show measured bit depth and sample rate when available, but that metadata display should not be interpreted as proof that the default catalog provides 24-bit or high-resolution streams. In particular, **24-bit / 88.2 kHz / 96 kHz support is not claimed for the built-in catalog endpoint** by the current repository audit. The sample rate of the active output route is shown separately from the media stream's sample rate.

For local files or another configured endpoint, the available format may differ. The app reports known values from the active asset and leaves unknown values blank rather than deriving them from a quality badge.

The native client uses HTTPS and its own truthful `User-Agent`. It does not spoof `Origin` or `Referer`, attach catalog credentials, or use the token-gated playback path. The endpoint can be enabled, disabled, changed, or reset in Settings; local files and existing downloads remain available when online catalog access is disabled.

For the endpoint investigation and request contract, see [`docs/ONLINE_STREAMING_AUDIT.md`](docs/ONLINE_STREAMING_AUDIT.md) and [`docs/STREAMING_START_INVESTIGATION.md`](docs/STREAMING_START_INVESTIGATION.md).

### Content and distribution notice

The catalog is Tidal-derived and its audio is relayed by a third-party host. The repository's Apache-2.0 license applies to the source code; it does **not** grant rights to third-party recordings, catalog metadata, or artwork. Source availability and personal use do not establish permission to redistribute the app or its content. Resolve the applicable service terms and content rights before publishing or distributing builds.

## Architecture

The application is divided into two Swift package targets:

### `MonochromeCore`

Portable Swift code for models, business rules, services, provider selection, playback state, and persistence. It is designed to remain independent of SwiftUI, UIKit, and AppKit so its behavior can be tested on Linux.

Core responsibilities include:

- Catalog clients, source providers, search, matching, selection, and stream resolution.
- Playback state, queue management, repeat and shuffle logic.
- Local library, favorites, history, playlists, downloads, and cache stores.
- Lyrics parsing, matching, timing, and caching.
- Audio quality/specification models and equalizer DSP logic.
- On-device recommendation and radio logic.

### `Monochrome`

The iOS application layer, built with SwiftUI and Apple media frameworks. It contains the app shell, views, AVFoundation playback engine, audio session and route integration, Now Playing controls, and the equalizer audio tap.

### Playback and data flow

The player resolves media through a concrete `PlaybackSource`. For supported tracks, playback checks permanent downloads first, then the temporary cache, and finally the network stream. `PlayerController` owns playback state and queue decisions; SwiftUI views render the state published by the controller.

Persistent application data is stored locally. Settings and lyric timing use `UserDefaults`; larger collections such as favorites, history, library indexes, playlists, equalizer settings, and download indexes use JSON-backed files in Application Support.

**Development rule:** put portable models and business logic in `MonochromeCore`, add host tests, and keep the SwiftUI layer focused on presentation and system integration.

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the full architecture notes.

## Build and test

### Requirements

- Swift 6.x toolchain.
- iOS 17 or later for the app target.
- Swift Package Manager.
- Linux x86-64 is supported for the portable core test workflow.
- For the documented Linux-to-iOS compile check: an installed Darwin Swift SDK.
- For device deployment: the configured `xtool` workflow and the required Apple device-signing/provisioning setup.
- No third-party Swift package dependencies.

### Run the portable test suite

```bash
swift --version
swift test
```

`MonochromeCore` uses portable Swift/Foundation APIs and can be tested on Linux without Xcode, an iOS simulator, or a connected iPhone.

### Cross-compile for iOS from Linux

```bash
scripts/build.sh
```

This runs the repository's SwiftPM iOS compile-check command for `arm64-apple-ios`. It verifies compilation; it does **not** create a signed IPA, install the app, or launch it on a device. The current command uses SwiftPM's `--build-system native` option for the documented toolchain compatibility reason. See [`docs/TOOLCHAIN_AUDIT.md`](docs/TOOLCHAIN_AUDIT.md).

### Optional live catalog test

The live catalog test is opt-in because it sends requests to the configured external service:

```bash
MONOCHROME_LIVE=1 swift test --filter LiveTracksAPITests
```

Run it only when you intend to contact the live catalog. It searches the service, resolves a stream, and checks the returned FLAC signature.

### Device build and installation

The repository includes [`xtool.yml`](xtool.yml) for the app's bundle identifier and resources. Device build and installation are manual operations, not CI tasks:

```bash
xtool dev build  # Build without deploying
xtool dev        # Install on a connected, provisioned device
```

Device installation depends on the local Apple signing and provisioning environment. The repository's CI does not access Apple credentials or physical devices.

## Continuous integration

GitHub Actions runs the portable Swift test suite on pushes and pull requests targeting `main` and `development`.

The workflow:

- Runs on `ubuntu-latest` with Swift 6.2.
- Executes `swift test -v`.
- Uses read-only repository permissions and does not require secrets.

CI validates the portable core test suite. It does **not** run the opt-in live catalog test, perform the Darwin iOS compile check, sign an app, produce a release IPA, or install the app on a physical iPhone.

[View workflow runs](https://github.com/KatsukiiNeko/monochrome-ios-native/actions/workflows/swift.yml).

## Repository layout

```text
.
├── Package.swift
├── Resources/
│   └── Info.plist
├── Branding/
│   ├── appicon.png
│   └── monochrome_logo.png
├── Sources/
│   ├── MonochromeCore/       # Portable models, services, state, and persistence
│   └── Monochrome/           # SwiftUI app and Apple-platform integrations
├── Tests/
│   └── MonochromeCoreTests/  # Portable unit tests and fixtures
├── scripts/
│   └── build.sh              # Linux-to-iOS compile check
├── docs/                     # Architecture, audits, and development notes
├── xtool.yml
├── NOTICE
└── license
```

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Device test checklist](docs/DEVICE_TEST_CHECKLIST.md)
- [Equalizer research](docs/EQ_RESEARCH.md)
- [Lyrics implementation](docs/LYRICS.md)
- [Online streaming audit](docs/ONLINE_STREAMING_AUDIT.md)
- [Streaming start investigation](docs/STREAMING_START_INVESTIGATION.md)
- [Source capabilities](docs/SOURCES.md)
- [Toolchain audit](docs/TOOLCHAIN_AUDIT.md)
- [Feature gap](docs/FEATURE_GAP.md)
- [Repository migration and attribution](docs/REPO_MIGRATION.md)

## License and attribution

The native application source is distributed under the [Apache License 2.0](license). See [`NOTICE`](NOTICE) and [`Branding/SOURCE.md`](Branding/SOURCE.md) for attribution and branding information.

The source-code license does not grant rights to third-party music recordings, catalog metadata, or artwork.

<p align="center">
  <sub>Native iOS development · SwiftUI · AVFoundation</sub>
</p>
