# Monochrome — Native iOS

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

<p align="center">
  <img
    src="Branding/monochrome_logo.png"
    alt="Monochrome logo"
    width="220"
  >
</p>

A native SwiftUI music player inspired by the [Monochrome web app](https://github.com/monochrome-music/monochrome). It plays audio imported from the iOS Files app and streams FLAC tracks from the public catalog endpoint used by Monochrome.

The app includes Home, Search, and Library tabs; a persistent mini-player; a full Now Playing screen; a queue; a sleep timer; favorites; play history; local audio caching; repeat modes; Lock Screen media controls; an honest audio specification for the current track; on-demand lyrics; and a parametric equalizer.

**Native app, not a WebView wrapper.** No account is required for the documented public catalog path. The app has no analytics or tracking SDKs and has no third-party Swift package dependencies.

> **Fork notice:** This repository is a native iOS derivative of [monochrome-music/monochrome](https://github.com/monochrome-music/monochrome). See [`docs/REPO_MIGRATION.md`](docs/REPO_MIGRATION.md), [`license`](license), [`NOTICE`](NOTICE), and [`Branding/SOURCE.md`](Branding/SOURCE.md) for project history, license, attribution, and branding provenance.

## Features

| Feature | Details |
|---|---|
| Local audio | Import audio from Files. The app copies imported files into its own storage; removing an item does not delete the original. |
| Online catalog | Search tracks, albums, and artists; open album and artist details; select tracks for playback. |
| Streaming | Resolve a playable track URL at playback time and retry resolution once after a playback failure. |
| Playback | Play/pause, seeking, next/previous, queue management, and repeat modes. |
| Library | Local library, favorites, and recently played history persisted on-device. |
| Permanent downloads | User-chosen songs are saved under Application Support/Downloads and play offline until removed. Downloads are separate from the temporary cache and imported files. |
| Audio cache | A five-song rolling on-disk LRU buffer. Playing songs 1–5 keeps all five; playing song 6 evicts song 1, so songs 2–6 still start from cache without re-streaming. Caching over cellular is disabled, and the cache is never cleared on launch. Cache cleanup never touches downloads or imported files. |
| Audio metadata | Displays the detected audio format and quality where available. Tapping the badge on Now Playing opens an Audio sheet with the measured codec, sample rate, bit depth, channels, bitrate, playback source and output route. Unknown values are omitted rather than inferred; each format value is marked measured or reported. |
| Equalizer | A ten-band graphic mode and a parametric mode with up to sixteen bands (peak, low and high shelf, low and high pass, notch), twenty original presets plus seventeen classic ones in graphic mode, automatic or manual preamp with a clip light, bass, clarity, stereo width and Dynamic Boost, user presets, and text import/export in the common parametric format. It runs in an audio tap, so it applies to progressive audio only: HLS and items without an audio track report the control as unavailable instead of pretending to work. See [`docs/EQ_RESEARCH.md`](docs/EQ_RESEARCH.md). |
| Sleep timer | Now Playing's overflow menu arms a 5, 15, 30, 45 or 60 minute timer. A countdown row under the scrubber can cancel it; at expiry playback pauses and keeps its position. The timer lasts for the session and is not persisted. |
| Lyrics | Synced or plain lyrics from [LRCLIB](https://lrclib.net), fetched only when the Lyrics sheet is opened. Synced lines follow playback, tapping a line seeks, and scrolling pauses follow until Follow is tapped. Lyrics compensate automatically for the active output route's measured latency and keep a per-track manual timing nudge. Loading, instrumental, not-found, offline and error states are explicit. See [`docs/LYRICS.md`](docs/LYRICS.md). |
| iOS integration | Background audio, Now Playing metadata with album and artwork, Lock Screen controls, remote commands, interruption handling, and route-change handling. |
| Preferences | System/Light/Dark appearance, a selectable state accent (Monochrome, Signal, Amber, Mint, Blue, Violet, or the current artwork's colour), an Enable Endpoint on/off switch, endpoint reset, cache clearing, download management, and project/licensing information. |
| Privacy | No account system, analytics, or tracking SDK. No credentials are embedded in the source. Lyrics are requested only when the lyrics view is opened, not for every song played; the request carries the track title, artist, album and duration, with no account or device identifier. |

Monochrome downloads are available because the upstream web client downloads the same progressive FLAC stream (`js/api.js:3050`, `js/downloads.js:348`). That is capability evidence, not a content licence: the rights caveat below still applies. The YouTube Music companion source has no server configured in this build and never downloads. Cloud playlists, account login, and cross-device synchronization are not implemented. See [`docs/SOURCES.md`](docs/SOURCES.md).

## Verification

The maintainer completed the physical-device test checklist and reports successful results for the 0.2.0 release, including the downloads, five-song cache, settings and Now Playing changes, on an iPhone 12 Pro Max. The accent-color controls, the audio specification, lyrics, and equalizer were added after that release and have been checked by host tests and the iOS compile check. The equalizer's audio path in particular has not been heard on hardware: whether it applies to streamed, cached, downloaded and remote-progressive items is unverified.

| Level | Meaning | Status |
|---|---|---|
| **L1 — Compile** | Swift sources compile for the target platform. | Passed |
| **L2 — Unit tests** | Portable core behavior is tested on Linux. | Passed: 367 tests across 37 suites at the last recorded run, including the equalizer filters, response curves, render chain, presets, persistence, text format and availability rules, plus the audio-info chip variants, audio-specification formatters, lyrics parser, matcher, cache, provider, service, timing store, and the core layering guard. |
| **L3 — Live service** | Catalog search and stream resolution are checked against the live catalog. | Passed in the recorded live-service checks; the opt-in live test is not run by default. Lyrics response shape and English/Vietnamese coverage were checked against LRCLIB from Linux; see [`docs/LYRICS.md`](docs/LYRICS.md). The upstream audio host was serving no data at the time of the equalizer work, so the tap could not be exercised against a real stream. |
| **L4 — Physical device** | Playback and iOS-specific behavior are checked on a real iPhone. | Passed for the 0.2.0 release on an iPhone 12 Pro Max. Not run for the equalizer: no device was attached during that work. |

CI runs the portable `swift test` suite. It does **not** run the live catalog test, build/sign an IPA, or install the app on a device. The iOS cross-compile check remains a separate local step because this workflow does not provision Apple's Darwin SDK.

## Streaming and audio quality

The default catalog path uses the public progressive FLAC endpoint:

```text
https://tracks.monochrome.st/track/<track-id>
```

The documented endpoint provides **FLAC, 16-bit / 44.1 kHz lossless audio**. It does not expose the website's `HI_RES_LOSSLESS` tier through this path.

The native client uses HTTPS and a truthful `User-Agent`; it does not spoof `Origin` or `Referer`, include credentials, or call the token-gated `/api/v2/track/` endpoint. The API client contains multi-host failover support and tests, but the current app wiring configures a single host; automatic user-host-to-default-host failover should not be considered an active app feature until that wiring is added.

In Settings, **Enable Endpoint** switches the online catalog and streaming on or off while retaining local playback. The catalog endpoint can be pointed at another HTTPS host (for example, your own instance or a supported paid endpoint) and reset to the built-in default without changing appearance, downloads, favorites or history.

"Hi-Fi" in this app is a quality label, not a separate catalogue or provider: the catalog path exposes one lossless tier (FLAC 16-bit / 44.1 kHz). YouTube Music has no authorized integration here; it is a companion-server design with no default URL. Permanent downloads store the same progressive FLAC stream the app plays, and the temporary cache is a separate disposable buffer.

### Content and distribution notice

The catalog is Tidal-derived and is relayed by a third-party host. The upstream repository's Apache-2.0 license covers source code; it does **not** grant rights to the catalog's recordings or artwork. The availability of a personal build does not establish permission to redistribute the app or its content. Resolve the applicable service terms and content rights before publishing or distributing builds. See [`docs/ONLINE_STREAMING_AUDIT.md`](docs/ONLINE_STREAMING_AUDIT.md).

## Build and test

### Requirements

- Swift 6.4 or compatible Swift 6.x toolchain for the portable core tests.
- Linux x86-64 for the documented local workflow.
- The Darwin Swift SDK and xtool 1.22 for the Linux iOS cross-compile and device workflow.
- No third-party Swift packages.

### Run the portable tests

```bash
swift --version
swift test
```

The portable `MonochromeCore` target uses Foundation and can be tested on Linux without Xcode, an iOS simulator, or a connected iPhone.

### Cross-compile for iOS on Linux

```bash
scripts/build.sh
```

This invokes the repository's documented SwiftPM iOS compile-check command. It checks compilation; it does not sign, package, install, or launch the application. The current script uses SwiftPM's `--build-system native` option because of the documented platform-resolution limitation in the tested Linux toolchain; SwiftPM reports that this option is deprecated, so this workflow may need updating with a future Swift release. See [`docs/TOOLCHAIN_AUDIT.md`](docs/TOOLCHAIN_AUDIT.md).

### Optional live catalog test

The live test sends requests to the configured third-party catalog and is deliberately excluded from the default CI run:

```bash
MONOCHROME_LIVE=1 swift test --filter LiveTracksAPITests
```

Run it only when you intend to contact the live service. It searches the catalog, resolves a stream, and checks the response's FLAC signature.

### Device build and installation

Device installation is a deliberate, manual operation and is not part of CI. The tracked `xtool.yml` holds the bundle identifier and resource settings. `xtool dev build` produces a build without deploying; `xtool dev` installs it on a connected device. The repository's CI does not access Apple credentials, provisioning profiles, or physical devices.

## CI

GitHub Actions runs `swift test` on pushes and pull requests targeting `main` or `development`. The workflow uses read-only repository permissions and requires no secrets. It validates the portable core; it does not claim to validate the iOS-only runtime layer or physical-device behavior.

## Architecture (brief)

The codebase is split into two layers:

- **MonochromeCore** — portable Swift (`Foundation`, `FoundationNetworking`, `Observation`). Models, stores, API client, cache, downloads, player state machine (`PlayerController`), equalizer DSP (`EQRuntime`, `EQFilters`, `EQChain`), lyrics provider and cache, and the formatted strings used by the UI. Tested on Linux.
- **Monochrome** — iOS-only SwiftUI and AVFoundation. Views, audio engine (`AVPlayerEngine`), audio session (`AudioSessionController`), Now Playing integration (`NowPlayingController`), equalizer tap (`EQTap`), and the app shell.

Playback order: downloaded file → cache hit → network resolution. The player controller decides; the view only shows what the controller publishes.

Persistence: UserDefaults for settings and per-track lyrics timing; JSON files in Application Support for favorites, history, library index, EQ settings/presets, and download index. Tolerant decoding and schema versions protect upgrades from older releases.

To add a feature: model and logic in `MonochromeCore` with host tests, then a thin SwiftUI binding in `Monochrome`.

## Repository layout

```text
Package.swift                    Swift package and targets
Resources/Info.plist             App display name and background audio capability
Branding/                        Upstream icon and logo attribution
scripts/build.sh                 Linux iOS compile check
Sources/MonochromeCore/          Portable models, stores, API client, cache, downloads, and player state
Sources/Monochrome/              SwiftUI interface and iOS audio integration
Tests/MonochromeCoreTests/        Unit tests and JSON fixtures
docs/                            Streaming, toolchain, migration, and device-test notes
```

## License and attribution

The native source is distributed under Apache-2.0; see [`license`](license) and [`NOTICE`](NOTICE). The upstream app icon and logo are included unchanged and are documented in [`Branding/SOURCE.md`](Branding/SOURCE.md). The code license does not grant rights to third-party recordings, catalog metadata, or artwork.