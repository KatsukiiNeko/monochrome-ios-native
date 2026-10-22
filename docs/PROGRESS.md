# Progress — native app, streaming and UI refresh

## Status

Work continues on `dev` off `main` at `9e85d63`. The native app (streaming,
search, resolve, play, retry, icon, tab shell, mini player, Now Playing, queue)
is unchanged in shape; two device defects are being fixed: catalog tracks do
not start playing, and no audio-format badge is shown. Verification so far is
**L1 + L2 + L3**; device runs are logged below as they happen.

## Milestones

| id | name | status | verification |
|---|---|---|---|
| R0 | baseline and git audit | done | L1 build + L2 tests on the imported HEAD, both green |
| R1 | replace `origin/main` | done | remote refs verified, backup branch created |
| R2 | streaming + UI audits, plan | done | reading only, live contract recorded |
| R3 | streaming vertical slice | done | L2 tests + L3 live request |
| R4 | app icon from the web app | done | byte-identical copy; `iconPath` matches the xtool schema |
| R5 | UI foundation (glass + tabs) | done | L1 |
| R6 | mini-player, Now Playing, queue | done | L1 |
| R7 | Search, Home, Library | done | L1 + L3 live catalog requests |
| R8 | regression pass | done | L1 + L2 + L3 rerun, all green |
| R9 | integrate and push `main` | done | remote ref verified with `git ls-remote` |
| R10 | handoff | done | final report |
| R11 | `dev` branch + device-testing rules | done | remote ref verified, `the contributor rules` updated |
| R12 | player/audio-session diagnostics | done | L1 build + L2 tests green |
| R13 | playable stream for AVPlayer | done | L1 build + L2 tests; device run pending |
| R14 | audio-format badge | done | L1 build + L2 tests |

## Baseline (R0, imported HEAD)

- Build-only check: green, arm64 Mach-O.
- Host tests: 44 tests in 5 suites, green.
- Working tree at the start had only ignored build output; `.gitignore` now also
  covers `xtool/` and `.bsp/`.

## Decisions

- **Streaming is Path A with a configurable host.** Default
  `https://tracks.monochrome.st`; Settings can change it or switch streaming
  off. No credentials ship, none are stored, and the token-gated path in the
  web app stays unused. Rationale and the rights caveat are in
  `docs/ONLINE_STREAMING_AUDIT.md`.
- **Stream URLs are built at play time** from `streamID` and never persisted.
  The player resolves again once after a failure, then shows an error with a
  Retry action.
- **Only CD-quality FLAC** (16-bit/44.1 kHz) is available on this path. The
  `application/octet-stream` response header is the main on-device risk.
- **Work happens on `dev`.** `dev` was created from `main` at `9e85d63` and is
  the only branch that is pushed. `main` stays as it was.
- **Device testing is allowed through `xtool dev`** from this repository against
  the connected iPhone, after a green build-only check and green host tests, one
  run at a time with `timeout`. Logs are read with `idevicesyslog` only.
- **The badge wording is the web app's.** `AudioBadge` maps a tier to the same
  text the site renders (`js/utils.js`: LOSSLESS → FLAC, HI_RES → HD FLAC,
  lossy → AAC) and, when the player has parsed the stream, to the real codec and
  sample format (`FLAC 16/44.1`, `HD 24/96`). Rows show the tier the catalog
  client declares; Now Playing prefers the parsed format. No badge without data.
- **Diagnostics use `os.Logger`** with subsystem `com.neko-ngtran.monochrome`
  and categories `player` / `audio-session`, values logged `.public` so
  `idevicesyslog` shows URLs and error domains. Cheap enough to keep
  permanently; it is the only way to see AVFoundation's error on the device.
- **Icon and logo are the web app's own artwork, unchanged.** `Branding/appicon.png`
  is a byte-identical copy of `public/assets/appicon.png` from `a3c86df`
  (1024×1024, already opaque); the SVGs are kept as sources. `iconPath` is a
  real key: `PackSchema.swift` in xtool 1.22.2 declares it and requires `.png`.
  Packing an `.app` needs `xtool dev`, which also installs, so the icon on the
  Home Screen is unverified (L4).
- **Liquid Glass is gated in one helper.** `glassEffect`/`GlassEffectContainer`
  do not exist in the installed SDK at all; only `.buttonStyle(.glass)` (iOS 26)
  does. `Theme.swift` wraps it with a bordered fallback, and system components
  (tab bar, navigation bars, sheets) get the new design from the OS on iOS 26.
  `tabViewBottomAccessory` is iOS 26, but its `isEnabled:` overload is 26.1, so
  the mini player's native accessory path is gated at 26.1 with a bottom inset
  fallback below that.
- **Favorites now store full tracks**, not ids, so streamed tracks survive a
  restart. The v1 id-only file is detected on load, resolved against the library
  and rewritten once. History is a separate capped file.

- **Migration:** `main` was fast-forwarded, not force-pushed. Old `main` is kept
  on `archive/webapp-main-before-native-2026-10-22` and `backup/pre-native-rebuild`.
  Hashes and the restore procedure live in `docs/REPO_MIGRATION.md`; PROGRESS
  intentionally holds none.
- **Build command stays** `swift build --build-system native --swift-sdk darwin
  --triple arm64-apple-ios`: the default SwiftBuild engine cannot resolve
  `iphoneos` on this host.
- **Swift 6 mode and the two-target split stay.** `MonochromeCore` holds portable
  logic (host-tested); `Monochrome` holds SwiftUI/AVFoundation behind
  `#if canImport(SwiftUI)`.
- **One player stays the source of truth.** Streaming resolves a URL at play
  time through `MusicService`; the UI and Now Playing keep reading
  `PlayerController`.
- Prior-run decisions that still hold: imports copy files into Application
  Support; persistence is Codable JSON; no third-party packages.

## Blockers

- **Device playback.** Catalog tracks did not play. Off-device, the stream URL
  answers `206` with `content-type: application/octet-stream`,
  `x-content-type-options: nosniff`, no URL extension, and the body starts with
  `fLaC`; the host does not serve `.flac` suffixes (`502`) and ignores a format
  query. `AVPlayer` therefore had to pick a demuxer from a generic type, and the
  previous code took `AVURLAsset.isPlayable` as the gate: either it refused the
  asset outright, or the item failed after the engine had already reported a
  start. Both paths are now handled (out-of-band MIME + item-status wait), but
  the exact device error could not be captured: `xtool dev` installs and signs
  the app on this host, yet does not launch it, and launching by other means is
  not permitted.
- **Badge wording source.** The catalog response has no quality field; the
  client declares `LOSSLESS` for this endpoint exactly as the web client does
  (`js/tracks-api.js`, `audioQuality: 'LOSSLESS'`), and the wording table is
  unit-tested. The codec shown on Now Playing comes from AVFoundation's parsed
  format description, never from the URL.
- **No device logs for the app.** The syslog capture during the install run only
  contains installation lines; there is no `Monochrome[pid]` line, no scene
  launch and no crash report, so the app was not started by the tool.
- No code blocker. Remaining unknowns are device-level only (L4): whether
  `AVPlayer` accepts the host's `application/octet-stream` FLAC, whether the
  `iconPath`/`resources` keys are packaged into the `.app`, and visual checks of
  the glass fallbacks. Nothing has been installed or run.
- Distribution is blocked by rights, not by code: the catalog is Tidal-derived
  and relayed by a third party, and the upstream repository has no content
  licence or terms. See `docs/ONLINE_STREAMING_AUDIT.md`.

## Commands that actually ran

| command | outcome |
|---|---|
| `scripts/build.sh` (on imported HEAD) | `Build complete!` (L1) |
| `swift test` (on imported HEAD) | 44 tests, 5 suites, green (L2) |
| `git ls-remote --heads origin` | only `refs/heads/main` at the old web-app commit |
| `git remote show origin` | fetch/push = `KatsukiiNeko/monochrome-ios-native`, HEAD branch `main` |
| `git fetch origin` / `git fetch upstream` | origin unchanged; upstream `main` at `86dc77aa…` |
| `git merge-base --is-ancestor <OLD> <NATIVE>` | exit 0, fast-forward |
| `git push origin <OLD>:refs/heads/archive/webapp-main-before-native-2026-10-22` | new branch |
| `git push origin <NATIVE>:refs/heads/main` | `a3c86df..d2b453d` |
| `git ls-remote origin refs/heads/main …` | main and archive refs match the expected SHAs |
| `swift test` after the API client and resolver | 68 tests in 9 suites, green (L2) |
| `MONOCHROME_LIVE=1 swift test --filter LiveTracksAPITests` | 1 test passed in 3.3 s: real search, real stream URL, 206 + `fLaC` (L3) |
| `scripts/build.sh` after the UI wiring | `Build complete!` (L1) |
| `swift test` after favorites/history and the UI | 73 tests in 10 suites, green (L2) |
| `scripts/build.sh` after the tab shell, Now Playing and search | `Build complete!` (L1) |
| `file`/`sha256sum` on `Branding/*` | 1024×1024 opaque PNG + SVG sources, hashes recorded in `Branding/SOURCE.md` |
| `touch Sources/**/*.swift && scripts/build.sh` (R8, forced recompile) | 39 compile steps, `Build complete!` (L1) |
| `swift test` (R8) | 73 tests in 10 suites, green (L2); baseline was 44 |
| `MONOCHROME_LIVE=1 swift test --filter LiveTracksAPITests` (R8) | passed in 2.1 s (L3) |
| `git merge-base --is-ancestor main feat/online-streaming-and-ui` before R9 | exit 0 (fast-forward possible) |
| `git merge --ff-only feat/online-streaming-and-ui` on `main` | fast-forward, no merge commit |
| `git push origin feat/online-streaming-and-ui` | `bad10ab..a892244` |
| `git push origin main` | `d2b453d..a892244` |
| `git ls-remote origin refs/heads/main refs/heads/archive/...` | `main` at `a89224428f35da7052a9b35211eb2d4a8d4156e0`, archive still `a3c86df0436a3eedc341ab5163fc5ee6b1688b5d` |
| `git switch -c dev` from `9e85d63`, `git push -u origin dev` | new branch; `dev` = `9e85d638058eff95309a16c110b992fe718078d0` |
| `git ls-remote origin refs/heads/dev` | matched the local `dev` SHA |
| `curl -r 0-1` / `HEAD https://tracks.monochrome.st/track/155142491052445696` | `206` / `200`, `application/octet-stream`, `content-range: bytes 0-1/39835632`, 39,835,632 bytes total, no extension in the path |
| `curl -r 0-1 -A 'AppleCoreMedia/1.0.0.21A360 (iPhone; U; CPU OS 17_0 like Mac OS X; en_us)'` | same `206`; the host does not reject a non-browser user agent |
| `swift test` after adding player diagnostics | 73 tests in 10 suites, green (L2) |
| `scripts/build.sh` after adding player diagnostics | `Build complete!` (L1) |
| `idevice_id -l` | `00008101-000868E222E9001E` |
| `curl -r 0-3 https://tracks.monochrome.st/track/<id>.flac` | `502`, `text/plain`; the host has no extension route |
| `curl -r 0-3 'https://tracks.monochrome.st/track/<id>?format=flac'` | `206`, still `application/octet-stream` |
| `timeout 600 xtool dev run --udid 00008101-000868E222E9001E` | build, provision, sign, install, verify all `100%`; app not launched |
| `timeout 900 idevicesyslog -u <udid> -m monochrome` during the install | install lines only, no app process |
| `swift test` after the stream-format fix | 74 tests in 10 suites, green (L2) |
| `scripts/build.sh` after the stream-format fix | `Build complete!` (L1) |
| `swift test` after the format badge | 81 tests in 11 suites, green (L2) |
| `scripts/build.sh` after the format badge | `Build complete!` (L1) |

## Deploy log

| # | commit | change | outcome |
|---|---|---|---|
| 1 | `707cc9a` | player/audio-session diagnostics | installed; not launched, no app logs |
| 2 | `1b008d5` | stream format, item readiness, format badge | installed; not launched, no app logs |

`xtool dev run` builds, provisions, signs, installs and verifies the app, then
exits without launching it. `idevicesyslog -m monochrome` during the run shows
installation lines only: no app process, no scene launch, no crash. Device-level
playback therefore stays unverified (L4 not reached) until the app is opened on
the phone by hand; `docs/DEVICE_TEST_CHECKLIST.md` covers what to check and how
to capture the player log.
