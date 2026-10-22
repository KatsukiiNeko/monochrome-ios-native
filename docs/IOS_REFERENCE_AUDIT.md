# iOS reference audit — `monochrome-ios` (untracked nested repo)

Static reading only, 2026-10-22: no build, no network, no execution. Claims are
`path:line`; anything about runtime, remote hosts, or device behavior is **Unverified**.
Describes the official iOS app, not the native rebuild in this repo.

## 1. Project shape

- One Xcode project, three targets (app, unit tests, UI tests):
  `monochrome-ios/monochrome.xcodeproj/xcshareddata/xcschemes/monochrome.xcscheme:19-51`.
- Deployment target **iOS 15.0** for all three targets:
  `monochrome-ios/monochrome.xcodeproj/project.pbxproj:464,523,553,580,606,632`.
- Swift **5** language mode: `project.pbxproj:480,539,565,592,618,644`; no strict-concurrency
  setting anywhere in the file.
- Project format is Xcode 16+: `objectVersion = 77` (`project.pbxproj:8`) with
  filesystem-synchronized groups, so every file under `monochrome/` is compiled implicitly
  (`project.pbxproj:42-58`); there is no explicit source file list to read.
- **No third-party dependencies**: no `XCRemoteSwiftPackageReference`, no Podfile, and all
  three frameworks phases are empty (`project.pbxproj:66-72,73-79,80-86`). Imports are Apple
  SDKs only: SwiftUI, Foundation, Combine, UIKit, AVFoundation, MediaPlayer,
  AuthenticationServices, PhotosUI, Observation.
- Size: 41 Swift files, 54 tracked files, 13,137 Swift lines.
- Entry point: `@main struct MonochromeIOSApp` (`monochrome-ios/monochrome/monochromeApp.swift:3-4`),
  which injects 8 `EnvironmentObject`s (`monochromeApp.swift:17-24`) and starts a 5-minute
  sync timer (`monochromeApp.swift:50-55`).
- Persistence is **UserDefaults + Codable JSON + JSON files in Caches**; no SwiftData, no
  Core Data, no Keychain (grep: zero hits for either framework).
  - Player state/queue/history: `monochrome-ios/monochrome/Services/AudioPlayerService.swift:196-205,755-841`
  - Favorites: `Services/LibraryManager.swift:13-17`
  - User playlists/folders: `Services/PlaylistManager.swift:10-11`
  - Profile: `Services/ProfileManager.swift:10`
  - Download manifest: `Services/DownloadManager.swift:10`
  - Auth session: `Services/AuthService.swift:17`
  - API cache: memory + per-key JSON files (`Services/CacheService.swift:28,88-90,150-164`)
- UI shell: four tabs via iOS 26 `Tab`/`.tabViewBottomAccessory` with a hand-rolled fallback
  tab bar (`Views/MainTabView.swift:68-105`, `:106-150`).

## 2. Feature map

| Feature | Status | Evidence |
|---|---|---|
| Search | implemented | `Services/MonochromeAPI.swift:56-126` (tracks/artists/albums/playlists, separate queries); 500 ms debounce + cancel `Views/SearchView.swift:673-679`; local query cache `SearchView.swift:482-500` |
| Streaming | implemented, fragile | `MonochromeAPI.swift:548-581` → Qobuz instance resolution `:506-546`; player `AudioPlayerService.swift:366-397` |
| Playback / queue | implemented | `AudioPlayerService.swift:323-429` (play), `:561-628` (next), `:630-707` (previous), shuffle/reorder `:230-321`; UI `Views/QueueSheetView.swift:3` |
| Library / favorites | implemented (local) + cloud | `Services/LibraryManager.swift:81-166` toggle, `:170-203` cloud merge; cloud requires login `PocketBaseService.swift:102-139` |
| Playlists | implemented | server playlists `MonochromeAPI.swift:414-443`, UI `Views/PlaylistDetailView.swift`; user playlists/folders CRUD `Services/PlaylistManager.swift:45-184`, sync `:188-259` |
| Lyrics | implemented | LRCLIB lookup `Views/LyricsView.swift:134-171`, LRC parse `:187-222`, cache `:126` |
| Downloads | implemented, no browser UI | `Services/DownloadManager.swift:71-150`; tag writing `Services/AudioMetadataEmbedder.swift:18-30`; per-track/album buttons `Views/NowPlayingView.swift:257-264`, `Views/AlbumDetailView.swift:17-22`; `downloadedCount` is defined but never read (`DownloadManager.swift:171`) |
| Auth | implemented | Appwrite REST `Services/AuthService.swift:9-10`; email/password `:35-45`; sign-up `:49-65`; Google via `ASWebAuthenticationSession` `:69-133`; session restore `:191-205` |
| Profile | implemented, unverified against server | read `Services/ProfileManager.swift:34-84`, write `:86+`; edit UI `Views/ProfileView.swift:382+`; avatar/banner upload `Services/ImageUploadService.swift:7,33-44` |
| Mixes | model only | `Mix` exists (`Models/Models.swift:86-95`) and is synced as a favorite, but there is no mixes endpoint call anywhere in `MonochromeAPI.swift` |

Everything above is L0/L1-shaped evidence: code paths exist, nothing here was executed.

## 3. Streaming

- Catalog is the same community Tidal-proxy API family the web app uses (`/search/`,
  `/album/`, `/artist/`, `/playlist/`), fetched from a rotating instance list with random
  start offset (`MonochromeAPI.swift:14-39`); instances are hardcoded
  (`Services/InstanceManager.swift:128-153`) and refreshed from a third-party uptime JSON
  (`InstanceManager.swift:37-40,204-255`).
- Audio is **not** obtained from `monochrome.tf`. The app resolves the Tidal track (ISRC) via
  the Tidal API with a hardcoded `X-Tidal-Token` (`MonochromeAPI.swift:487-504`), then asks
  Qobuz provider instances for `/api/get-music` and `/api/download-music`
  (`MonochromeAPI.swift:506-546`) and uses the returned URL directly.
- Quality mapping is numeric (`27/7/6/5`, `MonochromeAPI.swift:41-52`) with a downward
  fallback chain `hiRes → lossless → high → medium → low` (`:557-581`).
- Playback: `AVQueuePlayer` + `AVURLAsset`, one item at a time
  (`AudioPlayerService.swift:69,377-397`); a local download wins over streaming
  (`:366`); remote commands/Now Playing via MediaPlayer (`:515-559,733-751`).
- Error/expiry handling: only quality fallback. There is no HTTP check of the resolved audio
  URL, no `AVPlayerItem.status`/failed-to-play observation, and the sole item callback is
  `AVPlayerItemDidPlayToEndTime` (`:381-384`), whose handler runs off the main thread and
  calls `nextTrack()` (`:431-433`). A stream URL is resolved fresh on every play, so expiry
  between track start and mid-track failure is unhandled. If no ISRC match exists, the first
  Qobuz search hit is used (`MonochromeAPI.swift:524`) — wrong-track risk.

## 4. Test coverage

- Unit tests: a single empty `@Test` with no assertions
  (`monochrome-ios/monochromeTests/monochromeTests.swift:8-16`).
- UI tests: launch-only smoke test (`monochromeUITests/monochromeUITests.swift:26-40`) and a
  launch screenshot/performance test (`monochromeUITestsLaunchTests.swift:21-32`).
- Nothing asserts search, streaming, queue, sync, cache or tag writing. All testable logic
  lives in the app target (services import UIKit/AVFoundation and use singletons), so there is
  no host-compilable core; `TEST_HOST` points at the app binary
  (`project.pbxproj:567`), i.e. tests require an iOS simulator/destination.
- They could run only under macOS + Xcode (`swift-testing` runner for
  `import Testing`, `monochromeTests.swift:8`). Not runnable on Linux, not runnable via
  `swift test` against this package. CI does not run them at all — it only archives an IPA
  (`.github/workflows/ios.yml:33-56`).

## 5. Incompatible with the Linux/xtool toolchain

- **Asset catalog / `actool`**: `AssetCatalog` compile settings plus `AppIcon`/`AccentColor`
  names (`project.pbxproj:315,430-431`) and `monochrome/Assets.xcassets/**`. Linux SwiftPM
  cannot run `actool`; the icon would have to be replaced or pre-compiled. Whether xtool
  shims `actool` is **Unverified**.
- **iOS 26 SDK symbols compiled unconditionally**: `Tab`, `.tabViewBottomAccessory`
  (`MainTabView.swift:68-105`) inside `#available(iOS 26.0, *)`. Needs an SDK that knows those
  symbols; older SDKs fail to typecheck. Only relevant if the installed Darwin SDK is < 26 —
  **Unverified** here.
- **Project format**: `objectVersion 77` + `PBXFileSystemSynchronizedRootGroup`
  (`project.pbxproj:8,42-58`) is not readable by older project parsers or by SwiftPM.
- **MediaPlayer/AVFoundation** (`AudioPlayerService.swift:3`, `AudioMetadataEmbedder.swift:2`):
  unavailable on Linux; any rebuild must shim or drop Now Playing/remote commands.
- **AuthenticationServices** (`AuthService.swift:3,86`): web-auth session needs a UIKit window
  scene (`:104-117`); no Linux equivalent.
- **UIKit/PhotosUI** throughout, including `UIScreen.main.bounds`
  (`MainTabView.swift:15`, `CompatPhotoPicker.swift:2`) — deprecated/absent paths.
- **swift-testing** in the test target (`monochromeTests.swift:8`) requires an Xcode 16 test
  runner.
- Build entry points are Xcode-only: `build.sh:14-26` (`xcodebuild -sdk iphoneos`) and CI on
  `macos-26` (`.github/workflows/ios.yml:10,46`).
- Good news for a rebuild: no SPM packages, plugins, binary targets, storyboards, or
  XCTest-only framework dependencies.

## 6. Do not copy

- **Hardcoded third-party API token** in three places (`MonochromeAPI.swift:237,323,496`).
  Not reproduced here; do not carry it into new code.
- **Unauthenticated PocketBase access keyed by a client-supplied uid**
  (`PocketBaseService.swift:20,203`): requests carry no credential, only `?f_id=<uid>`, so
  trust rests entirely on unguessable ids (Unverified server-side). Every favorite toggle is
  read-modify-write of a whole JSON blob (`:102-139`) — lost updates under concurrency, and
  the 5-minute sync (`monochromeApp.swift:50-55`) multiplies the races.
- **Observation-on-top-of-ObservableObject hack**: `ObservationRegistrar` stored as `Any` with
  force casts plus `objectWillChange` fallback (`AudioPlayerService.swift:30-65`). Pick
  `@Observable` or `ObservableObject`, not both.
- **388-line hand-rolled FLAC/ID3v2.3/MP4 tag writer** (`AudioMetadataEmbedder.swift`,
  dispatch at `:18-30`). Format corruption risk, zero tests; prefer `AVAssetExportSession` or
  a maintained library.
- **`Compatibility.swift` (278 lines)** of iOS 15 shims (`:24-102,151-278`) for a claim no
  device evidence supports; only worth keeping if iOS 15 support is a real requirement.
- **Repeat-one re-streams over the network** instead of seeking to 0
  (`AudioPlayerService.swift:563-572`) — audible gap and a network dependency per loop.
- **DownloadManager progress delegate**: KVO observer added in `didCreateTask` and never
  removed (`DownloadManager.swift:222-239`); `downloadTracks` starts one task per track with
  no concurrency cap (`:146-150`).
- **Monolithic views**: `SearchView` 803, `LibraryView` 1064, `ProfileView` 1229,
  `ArtistDetailView` 885 lines. The artist loader alone has three fallbacks including direct
  Tidal calls (`MonochromeAPI.swift:236-304`).
- **Silent failure style**: 169 `try?` sites and 59 `print` calls; user-facing errors are
  mostly absent.
- Asset catalog carries macOS idiom entries in an iOS-only app
  (`Assets.xcassets/AppIcon.appiconset/Contents.json`).

## 7. License

- **No license file found** in `monochrome-ios/`: no `LICENSE`, `LICENCE`, `COPYING`, or
  `NOTICE`; no copyright/SPDX header in any of the 41 Swift files, `Info.plist`, or the
  workflow (grep across `monochrome/`, `monochromeTests/`, `monochromeUITests/`,
  `.github/`, `build.sh`).
- Nested repo origin: `https://github.com/monochrome-music/monochrome-ios`
  (`monochrome-ios/.git/config:6-7`). Whether the upstream repository declares a license is
  **Unverified** (no network access).
- The web app in this repo root is **Apache-2.0** (`license:1-3`, repo root, outside
  `monochrome-ios/`).
- Consequence: the licenses differ by default (Apache-2.0 documented vs. nothing documented
  for the iOS app), and absent a license file there is no grant to copy, modify, or
  redistribute that code — all rights reserved. **Do not copy code from `monochrome-ios/`
  into this repo**; reimplement from observed behavior and public API shapes only. If an
  Apache-2.0 grant is later confirmed for that repo, copying also requires keeping its
  attribution/NOTICE and marking modified files.
