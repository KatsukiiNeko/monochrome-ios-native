# Progress — native app, streaming and UI refresh

## Status

R8 complete: streaming (search, resolve, play, retry), the web app's icon and
logo, and the new UI (Home / Search / Library tabs, persistent mini player, Now
Playing, queue, album and artist sheets) are implemented, and the full
regression pass is green. Next: R9 integration.

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
| R9 | integrate and push `main` | todo | remote ref verified |
| R10 | handoff | todo | report |

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
