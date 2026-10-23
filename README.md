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

The app includes Home, Search, and Library tabs; a persistent mini-player; a full Now Playing screen; a queue; favorites; play history; local audio caching; repeat modes; and Lock Screen media controls.

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
| Audio cache | Temporary five-track on-disk LRU cache; caching over cellular is opt-in. Cache cleanup never touches imported files. |
| Audio metadata | Displays the detected audio format and quality where available. |
| iOS integration | Background audio, Now Playing metadata with album and artwork, Lock Screen controls, remote commands, interruption handling, and route-change handling. |
| Preferences | System/Light/Dark appearance, streaming host, and temporary-cache controls. |
| Privacy | No account system, analytics, or tracking SDK. No credentials are embedded in the source. |

Permanent catalog downloads are not offered. The catalog has no authorized download API, and the app does not treat temporary cache entries as downloads. YouTube Music is not integrated; the Monochrome catalog and user-imported files are the only playback sources. Lyrics, cloud playlists, account login, and cross-device synchronization are not implemented.

## Verification

The maintainer completed the physical-device test checklist for the earlier UI pass and reports successful results. The current settings, five-track cache and Now Playing changes were compiled and host-tested, but not installed or run on a device.

| Level | Meaning | Status |
|---|---|---|
| **L1 — Compile** | Swift sources compile for the target platform. | Passed |
| **L2 — Unit tests** | Portable core behavior is tested on Linux. | Passed: 152 tests across 21 suites at the last recorded run. |
| **L3 — Live service** | Catalog search and stream resolution are checked against the live catalog. | Passed in the recorded live-service checks; the opt-in live test is not run by default. |
| **L4 — Physical device** | Playback and iOS-specific behavior are checked on a real iPhone. | Passed for the earlier UI pass; the current settings/cache/Now Playing changes are not device-validated. |

CI runs the portable `swift test` suite. It does **not** run the live catalog test, build/sign an IPA, or install the app on a device. The iOS cross-compile check remains a separate local step because this workflow does not provision Apple's Darwin SDK.

## Streaming and audio quality

The default catalog path uses the public progressive FLAC endpoint:

```text
https://tracks.monochrome.st/track/<track-id>
```

The documented endpoint provides **FLAC, 16-bit / 44.1 kHz lossless audio**. It does not expose the website's `HI_RES_LOSSLESS` tier through this path.

The native client uses HTTPS and a truthful `User-Agent`; it does not spoof `Origin` or `Referer`, include credentials, or call the token-gated `/api/v2/track/` endpoint. The API client contains multi-host failover support and tests, but the current app wiring configures a single host; automatic user-host-to-default-host failover should not be considered an active app feature until that wiring is added.

In Settings, you can configure a different HTTPS host (for example, your own instance or a supported paid endpoint) or clear the host to disable online streaming while retaining local playback.

“Hi-Fi” in this app is a quality label, not a separate catalogue or provider: the catalog path exposes one lossless tier (FLAC 16-bit / 44.1 kHz). YouTube Music has no authorized integration here. Permanent downloads are also not implemented because the catalog provides no authorized download entitlement; the temporary cache is disposable and separate from imported files.

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

## Repository layout

```text
Package.swift                    Swift package and targets
Resources/Info.plist             App display name and background audio capability
Branding/                        Upstream icon and logo attribution
scripts/build.sh                 Linux iOS compile check
Sources/MonochromeCore/          Portable models, stores, API client, cache, and player state
Sources/Monochrome/              SwiftUI interface and iOS audio integration
Tests/MonochromeCoreTests/        Unit tests and JSON fixtures
docs/                            Streaming, toolchain, migration, and device-test notes
```

## License and attribution

The native source is distributed under Apache-2.0; see [`license`](license) and [`NOTICE`](NOTICE). The upstream app icon and logo are included unchanged and are documented in [`Branding/SOURCE.md`](Branding/SOURCE.md). The code license does not grant rights to third-party recordings, catalog metadata, or artwork.
