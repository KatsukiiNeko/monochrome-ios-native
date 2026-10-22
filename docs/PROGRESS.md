# Progress — native rebuild

## Status

M12 complete. The app is a compile-checked (L1) local-file player with a
host-tested core (L2). Nothing was installed, deployed or pushed.

## Milestones

| id | name | status | verification |
|---|---|---|---|
| M0 | safety baseline | done | backup + branch |
| M1 | audit upstream + official iOS reference | done | reading only |
| M2 | toolchain audit and spike | done | commands run |
| M3 | streaming feasibility | done | live contract check (L3 for the remote path, which was rejected) |
| M4 | implementation plan | done | n/a |
| M5 | clean the root | done | three reviewed commits |
| M6 | scaffold native package | done | L1 + L2 |
| M7 | data layer | done | L2 |
| M8 | player core | done | L2 |
| M9 | AVPlayer engine + UI | done | L1 |
| M10 | system integration | done | L1 only |
| M11 | extras | done (queue, favorites, artwork; recents and lyrics dropped) | L1/L2 |
| M12 | finalize | done | docs + status |

## Decisions

- Path B (local files): the only streaming source relays Tidal through an
  unauthenticated host — see `docs/STREAMING_FEASIBILITY.md`.
- Build-only command: `swift build --build-system native --swift-sdk darwin --triple arm64-apple-ios`.
  The default SwiftBuild engine fails with `unable to find platform for 'iphoneos'`.
- Swift 6 language mode held; `#if canImport(SwiftUI)` keeps the iOS target
  compiling to an empty module on Linux so `swift test` builds the whole package.
- `@Observable` works on both the Linux host and iOS, so `PlayerController` lives
  in the portable core and views observe it directly.
- Imports copy files into Application Support instead of storing security-scoped
  bookmarks: fewer failure modes, at the cost of disk space.
- Dropped recents/history and lyrics: recents would need playback events from
  auto-advance tracks and lyrics had no legitimate source after Path A was
  rejected. No UI control exists for either.
- Git identity was already configured; no repo-local override was needed.

## Blockers

None open. Everything that needs hardware (Playback, background audio, Lock
Screen, interruptions, route changes, artwork tags) is unverified and marked so
in the README.

## Commands that actually ran

| command | outcome |
|---|---|
| `swift --version` | 6.4.1 |
| `xtool --version` | 1.22.2 |
| `swift sdk list` | `darwin` |
| `xtool sdk status` | Darwin SDK installed (slim) |
| `swift build --build-system native --swift-sdk darwin --triple arm64-apple-ios` | builds arm64 Mach-O |
| `scripts/build.sh` | same command, green (L1) |
| `swift test` | 44 tests in 5 suites, green (L2) |
| `curl 'https://tracks.monochrome.st/search/tracks?q=daft%20punk&limit=2'` | 200 JSON |
| `curl -H 'Range: bytes=0-1023' 'https://tracks.monochrome.st/track/155102871061270528'` | 206, `fLaC`, 40 MB total |
| `idevice_id -l` | `ERROR: Unable to retrieve device list!` (read-only, no device) |
| `env -u LD_LIBRARY_PATH ldd $(command -v swiftc)` | no missing libraries |
