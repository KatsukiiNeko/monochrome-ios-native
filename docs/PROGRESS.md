# Progress — native rebuild

## Status

M1 (audits) complete. Next: M2 toolchain spike write-up, then M3 streaming
feasibility.

## Milestones

| id | name | status | verification |
|---|---|---|---|
| M0 | safety baseline | done | n/a |
| M1 | audit upstream + official iOS reference | done | reading only |
| M2 | toolchain audit and spike | doing | commands run |
| M3 | streaming feasibility | todo | — |
| M4 | implementation plan | todo | — |
| M5 | clean the root | todo | — |
| M6 | scaffold native package | todo | — |
| M7 | data layer | todo | — |
| M8 | player core | todo | — |
| M9 | AVPlayer engine + minimal UI | todo | — |
| M10 | system integration | todo | — |
| M11 | extras | todo | — |
| M12 | finalize | todo | — |

## Decisions

- Branch `native-rebuild` created from `main` HEAD; `backup/pre-native-rebuild`
  already existed at the same commit. Remote `origin` has push URL `DISABLED`.
- `monochrome-ios/` is an **untracked nested git repo** (own `.git`), so it is
  protected only by the tarball backup `~/monochrome-backup-20261022-1234.tar.gz`
  and the read-only copy `~/monochrome-reference/`.
- Entire working tree (incl. untracked `the contributor rules`, `page_content.html`,
  `get-html.ts`) backed up before any edit; 503 entries verified.
- Build-only command: `swift build --build-system native --swift-sdk darwin
  --triple arm64-apple-ios`. The default SwiftBuild engine cannot resolve the
  `iphoneos` platform on this host; the deprecated-but-working `native` build
  system can.
- Git identity already set (`katsukii Neko <katsukii.works@gmail.com>`), so no
  repo-local identity was needed.
- `APPIMAGELAUNCHER_DISABLE` / `LD_LIBRARY_PATH` are unset; `env -u
  LD_LIBRARY_PATH ldd <swiftc>` reports no missing libraries, so the RUNPATH
  workaround already in place is sufficient.
- Commit convention in history is inconsistent (`Update package.json`, `shit`,
  `nq`, plus some Conventional Commits). New commits use Conventional Commits
  per the mission contract.

## Blockers

None yet.

## Commands

| command | outcome |
|---|---|
| `git --no-pager log --oneline -20` | history is a fork of monochrome-music/monochrome with noisy messages |
| `tar` backup + `tar -tzf` | 19M archive, 503 entries, includes nested `monochrome-ios/.git/HEAD` |
| `swift --version` | 6.4.1 (x86_64-unknown-linux-gnu) |
| `xtool --version` | 1.22.2 |
| `swift sdk list` | `darwin` |
| `xtool sdk status` | Darwin SDK installed (slim, iPhoneOS27.1.sdk) |
| `swift build --swift-sdk darwin --triple arm64-apple-ios` | fails: `unable to find platform for 'iphoneos'` |
| `swift build --build-system native --swift-sdk darwin --triple arm64-apple-ios` | builds arm64 Mach-O objects |
| `swift test` | passes a `@Test` in the portable core while the iOS target builds as an empty module on Linux |
