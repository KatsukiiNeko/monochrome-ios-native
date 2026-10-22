# Progress — native app, streaming and UI refresh

## Status

R1 complete: `origin/main` now holds the native app (fast-forward from the old
web-app commit), with a remote backup branch. Next: R2 audits, then the
streaming vertical slice.

## Milestones

| id | name | status | verification |
|---|---|---|---|
| R0 | baseline and git audit | done | L1 build + L2 tests on the imported HEAD, both green |
| R1 | replace `origin/main` | done | remote refs verified, backup branch created |
| R2 | streaming + UI audits, plan | todo | reading only |
| R3 | streaming vertical slice | todo | target L2 tests + L3 live contract |
| R4 | app icon from the web app | todo | file-level evidence |
| R5 | UI foundation (glass + tabs) | todo | L1 |
| R6 | mini-player, Now Playing, queue | todo | L1 |
| R7 | Search, Home, Library | todo | L1 |
| R8 | regression pass | todo | L1 + L2 rerun |
| R9 | integrate and push `main` | todo | remote ref verified |
| R10 | handoff | todo | report |

## Baseline (R0, imported HEAD)

- Build-only check: green, arm64 Mach-O.
- Host tests: 44 tests in 5 suites, green.
- Working tree at the start had only ignored build output; `.gitignore` now also
  covers `xtool/` and `.bsp/`.

## Decisions

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

- Previously rejected: `tracks.monochrome.st` relays Tidal-derived audio without
  rights. Re-examined in R2 against the current upstream tree; the outcome is
  recorded in `docs/ONLINE_STREAMING_AUDIT.md`.

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
