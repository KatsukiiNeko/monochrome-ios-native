<p align="center">
  <img src="Branding/monochrome_logo.png" alt="Monochrome logo" width="180">
</p>

<h1 align="center">Monochrome Native</h1>

<p align="center">
  <strong>A native SwiftUI music player for iOS. Lossless streaming, your own files, synced lyrics, and zero tracking.</strong>
</p>

<p align="center">
  <a href="#features">Features</a> -
  <a href="#quick-start">Quick Start</a> -
  <a href="#streaming-and-audio-quality">Streaming</a> -
  <a href="#status">Status</a> -
  <a href="#repository-layout">Layout</a> -
  <a href="#license-and-attribution">License</a>
</p>

<p align="center">
  <a href="https://github.com/KatsukiiNeko/monochrome-ios-native/actions">
    <img src="https://img.shields.io/github/actions/workflow/status/KatsukiiNeko/monochrome-ios-native/swift.yml?branch=main&style=for-the-badge&logo=githubactions&label=CI" alt="CI status">
  </a>
  <img src="https://img.shields.io/badge/Swift-6.4-F05138?style=for-the-badge&logo=swift&logoColor=white" alt="Swift 6.4">
  <img src="https://img.shields.io/badge/Framework-SwiftUI-blue?style=for-the-badge&logo=swift" alt="SwiftUI">
  <img src="https://img.shields.io/badge/Platform-iOS-black?style=for-the-badge&logo=apple" alt="iOS">
  <a href="license">
    <img src="https://img.shields.io/badge/License-Apache--2.0-blue?style=for-the-badge" alt="Apache 2.0 License">
  </a>
</p>

---

## What is Monochrome Native?

**Monochrome Native** is a fully native iOS take on the [Monochrome web app](https://github.com/monochrome-music/monochrome): a clean, minimal, ad-free music player built in SwiftUI. Stream lossless FLAC from the public catalog, import your own audio from Files, follow synced lyrics, and control everything from the Lock Screen.

**Native, not a WebView wrapper.** No account required. No analytics or tracking SDKs. No third-party Swift packages.

> **Fork notice:** This repository is a native iOS derivative of [monochrome-music/monochrome](https://github.com/monochrome-music/monochrome). See [`docs/REPO_MIGRATION.md`](docs/REPO_MIGRATION.md), [`license`](license), [`NOTICE`](NOTICE), and [`Branding/SOURCE.md`](Branding/SOURCE.md) for project history, license, attribution, and branding provenance.

---

## Features

### Audio Quality

- Lossless FLAC streaming (16-bit / 44.1 kHz) from the public catalog endpoint
- Live audio specification: tap the quality badge on Now Playing to see codec, sample rate, bit depth, channels, bitrate, playback source and output route, with each value marked as measured or reported
- Format and quality badges on tracks
- Five-song rolling on-disk cache (LRU): play songs 1-5, then song 6, and songs 2-6 still start instantly without re-streaming
- Cache stays off cellular and is never cleared on launch

### Interface

- Home, Search, and Library tabs
- Persistent mini-player and full Now Playing screen
- System, Light, and Dark appearance
- Selectable accent: Monochrome, Signal, Amber, Mint, Blue, Violet, or the colour of the current artwork
- Queue view with full queue management

### Library & Organization

- Import audio from the Files app (files are copied into the app's own storage; removing an item never deletes the original)
- Search tracks, albums, and artists, with album and artist detail pages
- Favorites and recently played history, persisted on-device
- Repeat modes and next/previous controls
- Permanent downloads: save songs you choose for offline playback, kept separate from the temporary cache and from imported files

### Lyrics

- Synced and plain lyrics from [LRCLIB](https://lrclib.net)
- Synced lines follow playback; tap any line to seek; scroll to pause follow, tap Follow to resume
- Automatic compensation for the active output route's measured latency, plus a per-track manual timing nudge
- Clear loading, instrumental, not-found, offline, and error states
- Fetched only when you open the Lyrics sheet (see [`docs/LYRICS.md`](docs/LYRICS.md))

### iOS Integration

- Background audio
- Lock Screen controls and remote commands
- Now Playing metadata with album and artwork
- Interruption and route-change handling
- Sleep timer (5, 15, 30, 45, or 60 minutes) from the Now Playing menu, with a countdown row under the scrubber

### Settings & Control

- **Enable Endpoint** switch for online catalog and streaming, while local playback keeps working
- Point the catalog at your own HTTPS host and reset it to the default at any time
- Clear cache and manage downloads without touching appearance, favorites, or history

### Privacy

- No account system, analytics, or tracking SDK
- No credentials embedded in the source
- Lyrics requests carry only track title, artist, album, and duration, with no account or device identifier, and are sent only when the lyrics view is opened

---

## Quick Start

### Requirements

- Swift 6.4 or a compatible Swift 6.x toolchain
- Linux x86-64 for the documented local workflow
- Darwin Swift SDK and xtool 1.22 for iOS cross-compile and device builds
- No third-party Swift packages

### Run the tests

```bash
swift --version
swift test
```

The portable `MonochromeCore` target uses Foundation only, so it tests on Linux without Xcode, a simulator, or a connected iPhone.

### Cross-compile for iOS on Linux

```bash
scripts/build.sh
```

Runs the repository's SwiftPM iOS compile check. It verifies compilation; it does not sign, package, install, or launch the app. The script uses SwiftPM's `--build-system native` option because of a platform-resolution limitation in the tested Linux toolchain, so it may need updating with a future Swift release. See [`docs/TOOLCHAIN_AUDIT.md`](docs/TOOLCHAIN_AUDIT.md).

### Install on your iPhone

Device installation is a deliberate, manual step and is not part of CI. Bundle identifier and resource settings live in the tracked `xtool.yml`.

```bash
xtool dev build   # build without deploying
xtool dev         # build and install on a connected device
```

### Optional live catalog test

Contacts the real third-party catalog, so it is excluded from the default CI run:

```bash
MONOCHROME_LIVE=1 swift test --filter LiveTracksAPITests
```

It searches the catalog, resolves a stream, and checks the response's FLAC signature.

---

## Streaming and Audio Quality

The default catalog path uses the public progressive FLAC endpoint:

```text
https://tracks.monochrome.st/track/<track-id>
```

- **Quality:** FLAC, 16-bit / 44.1 kHz lossless. This path offers one lossless tier; the website's `HI_RES_LOSSLESS` tier is not exposed through it, so "Hi-Fi" in the app is a quality label rather than a separate catalogue.
- **Respectful client:** HTTPS only, a truthful `User-Agent`, no spoofed `Origin` or `Referer`, no credentials, and no calls to the token-gated `/api/v2/track/` endpoint.
- **Resilient playback:** the stream URL is resolved at playback time, and resolution is retried once after a playback failure.
- **Downloads:** permanent downloads store the same progressive FLAC stream the app plays, matching what the upstream web client does (`js/api.js:3050`, `js/downloads.js:348`).

See [`docs/SOURCES.md`](docs/SOURCES.md) for the source design.

---

## Status

| Level | What it covers | Result |
|---|---|---|
| **L1 - Compile** | Swift sources compile for the iOS target | Passed |
| **L2 - Unit tests** | Portable core behavior on Linux | Passed: 309 tests across 35 suites at the last recorded run |
| **L3 - Live service** | Catalog search and stream resolution against the live catalog | Passed in recorded checks; the live test is opt-in |
| **L4 - Physical device** | Playback and iOS behavior on a real iPhone | Passed: v0.3.0 verified on an iPhone 12 Pro Max |

The v0.3.0 device checklist covered playback, downloads, the five-song cache, Settings, Now Playing and Lock Screen metadata, sleep timer, synced lyrics with the automatic output delay, audio specification, accent colors, background playback, and accessibility settings. The attached unsigned IPA was validated structurally, not installed on the device.

CI runs `swift test` on pushes and pull requests to `main` or `development`, with read-only permissions and no secrets. It validates the portable core; it does not run the live catalog test, build an IPA, or install on a device.

### Not implemented yet

- Cloud playlists, account login, and cross-device sync
- A configured YouTube Music companion source (the design exists, but no server is configured in this build and it never downloads)
- Automatic failover to the default host (the API client supports multi-host failover, but the app currently wires a single host)

---

## Content and Distribution Notice

The catalog is Tidal-derived and relayed by a third-party host. The Apache-2.0 license covers this project's source code. It does **not** grant rights to the catalog's recordings, metadata, or artwork, and a working personal build does not establish permission to redistribute the app or its content. Review the applicable service terms and content rights before publishing or distributing builds. See [`docs/ONLINE_STREAMING_AUDIT.md`](docs/ONLINE_STREAMING_AUDIT.md).

---

## Repository Layout

```text
Package.swift                    Swift package and targets
Resources/Info.plist             App display name and background audio capability
Branding/                        Upstream icon and logo attribution
scripts/build.sh                 Linux iOS compile check
Sources/MonochromeCore/          Portable models, stores, API client, cache, downloads, player state
Sources/Monochrome/              SwiftUI interface and iOS audio integration
Tests/MonochromeCoreTests/       Unit tests and JSON fixtures
docs/                            Streaming, toolchain, migration, and device-test notes
```

---

## License and Attribution

The native source is distributed under Apache-2.0; see [`license`](license) and [`NOTICE`](NOTICE). The upstream app icon and logo are included unchanged and documented in [`Branding/SOURCE.md`](Branding/SOURCE.md).

<p align="center">
  Built on the ideas of <a href="https://github.com/monochrome-music/monochrome">Monochrome</a>, rebuilt natively for iOS.
</p>
